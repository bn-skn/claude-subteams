#!/bin/bash
# coord.sh — portable multi-instance coordination for claude-subteams.
#
# A small, file-based substrate (flock + jq JSON + per-instance inbox) so 2-3 identical
# Claude Code instances on ONE machine, working ONE git repo (each in its own worktree),
# can coordinate WITHOUT depending on Claude Code's native agent-teams. Opt-in only.
#
# Activation: nothing here does anything unless CLAUDE_SUBTEAMS_MULTI_INSTANCE=1.
# Liveness: we register the LONG-LIVED instance process pid — resolved by walking up the
# process tree to the persistent `claude` ancestor, NOT the hook's ephemeral $PPID (an
# `sh -c` shell that dies the instant the hook returns; registering it reaped every
# instance on the first pass). When that resolution succeeds the entry is `pid_trusted`
# and liveness is authoritative by PID (`kill -0`): a quiet instance is never wrongly
# reaped, a dead one is reaped at once. Only when the real pid is UNobtainable do we fall
# back to a heartbeat TTL (CLAUDE_SUBTEAMS_HEARTBEAT_TTL). A removed worktree is an
# unconditional dead signal. Claims are ADVISORY (cooperating instances honor them).
#
# Layout (shared across all worktrees of one repo, keyed by --git-common-dir):
#   $COORD_HOME/<repokey>/
#     instances.json   { id: {pid, worktree, branch, role, started, heartbeat} }
#     claims.json      { "relpath": {by, at} }
#     inbox/<id>.jsonl  append-only messages for <id>
#     inbox/<id>.bad.jsonl  quarantined malformed inbox lines (capped at 200, see recv)
#     lock              flock target for instances/claims read-modify-write
#     commit.lock       flock target for serialized git commits
#     gate.lock         flock target for serialized heavy gates (tsc+vitest+canary)
#
# Usage: coord.sh <command> [args]
#   init                               ensure coord dir + files exist (atomic)
#   register  --id ID [--worktree P --branch B --role R]
#                                      *** exit 6 = SUCCESS, WITH a warning: the instance
#                                      IS registered, just over CLAUDE_SUBTEAMS_MAX_INSTANCES.
#                                      Callers MUST treat 6 as success (a `register ... &&`
#                                      chain, `if register; then`, or a `set -e` script must
#                                      NOT abort on it) — only exit 8 means registration
#                                      itself failed. ***
#                                      exit 8 = ledger write failed, instance NOT registered
#   deregister --id ID                 remove instance + release its claims
#   heartbeat --id ID [--pid P --worktree P --branch B]  refresh liveness; re-register if reaped
#   roster                             list live instances (reaps dead first)
#   reap                               remove dead instances + release their claims
#   count                              print live-instance count as ONE bare integer, nothing
#                                      else (reaps dead first; machine-readable — unlike
#                                      roster's prose, this output format is a stable contract)
#   claim     --id ID PATH...          atomic claim-or-reject, all-or-nothing across the
#                                      batch (exit 0 = all claimed, 3 = >=1 held by a peer;
#                                      1 = internal jq/ledger failure, nothing written)
#   release   --id ID [PATH... | --all]  release listed (or all) of an instance's claims
#                                      (a file literally named '--all' can't be released
#                                      by name — the flag wins; pathological, documented)
#   claims                             list current claims
#   send      --from ID --to ID MSG    append MSG to recipient inbox
#   recv      --id ID [--count]         print + clear own inbox (--count: peek count, no clear)
#   notify-due --id ID                  echo unread count IF new since last notify, else 0 (throttle)
#   commit-lock -- CMD...              run CMD holding the global commit lock (see gate-lock:
#                                      always take gate-lock OUTSIDE commit-lock, never nested
#                                      the other way — avoids an ABBA deadlock between the two)
#   gate-lock [--timeout N] -- CMD...  run CMD holding the gate lock (serializes heavy
#                                      tsc/vitest/canary gates; no --timeout = wait
#                                      forever; --timeout N: exit 75 if not acquired in Ns;
#                                      CMD's own exit code is always passed through — 75 is
#                                      reserved so a gate that itself exits 75 is never
#                                      confused with coord's own timeout)
#   repokey                            print the derived repo key (debug)

set -uo pipefail

# ---- Opt-in gate: the very first thing. Unset → no-op, exit clean. ----
if [ "${CLAUDE_SUBTEAMS_MULTI_INSTANCE:-0}" != "1" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[coord] jq is required for multi-instance mode but was not found." >&2
  exit 1
fi

COORD_HOME="${CLAUDE_SUBTEAMS_COORD_HOME:-$HOME/.claude/subteams}"

# Heartbeat TTL (seconds): a PID-dead instance whose heartbeat is older than this is
# considered gone. The registered pid is only an accelerator, NOT authoritative — on
# SDK/service harnesses the SessionStart pid is an ephemeral hook shell that dies at
# once, so heartbeat freshness is the real liveness signal. Generous default so an
# instance idling between user turns survives; override via CLAUDE_SUBTEAMS_HEARTBEAT_TTL.
HEARTBEAT_TTL="${CLAUDE_SUBTEAMS_HEARTBEAT_TTL:-1800}"

# Soft cap on simultaneously live instances. Claude Code has NO cross-session resource
# awareness — nothing stops N sessions from collectively saturating one box's CPU/RAM,
# especially once each is running heavy gates (tsc+vitest+canary boot). 5 is the top of
# Anthropic's own team-size guidance ("three focused often beats five scattered"); past
# that, gate contention (see gate-lock below) starts to dominate on a 6 vCPU-class host.
# This is advisory, not a hard reject — see the comment in cmd_register for why.
MAX_INSTANCES="${CLAUDE_SUBTEAMS_MAX_INSTANCES:-5}"
# Same "reject non-integer, warn, fall back to a safe default" pattern used elsewhere in
# this file (see e.g. gate-lock's --timeout validation) — an unset/garbage value must
# never silently disable the cap (a literal '[: abc: integer expression expected' on
# every register call, with the cap never actually enforced, is exactly that failure).
case "$MAX_INSTANCES" in
  ''|*[!0-9]*)
    echo "[coord] CLAUDE_SUBTEAMS_MAX_INSTANCES='$MAX_INSTANCES' is not a non-negative integer — falling back to default 5." >&2
    MAX_INSTANCES=5
    ;;
esac

_now() { date +%s; }

# Identity sanity: ids and inbox targets become filenames and jq keys — reject anything
# that could traverse the coord dir or break the ledger. Session-hash ids are [a-f0-9].
_valid_id() { printf '%s' "${1:-}" | grep -qE '^[A-Za-z0-9._-]+$'; }

# Reject empty paths and paths with embedded newlines: plist building is line-based
# (jq -R), a newline would silently split one path into two ledger keys.
_valid_paths() {  # _valid_paths <cmd-name> <path>...
  local cmd="$1" p; shift
  for p in "$@"; do
    case "$p" in
      ''|*$'\n'*) echo "[coord] $cmd: empty path or path with newline rejected" >&2; return 2;;
    esac
  done
}

# Resolve the long-lived instance process pid: walk up the parent chain from <start>
# (default $PPID) until a persistent agent process is found. Hooks (and this script)
# run as transient `sh -c`/bash children of the session's `claude` process, so the
# stable, per-instance, session-long pid is an ANCESTOR — not $PPID. Prints the pid and
# returns 0 on success; returns 1 if no such ancestor exists (e.g. run outside a session,
# under cron, or on a harness with a different process name) — callers then fall back to
# a heartbeat TTL. Bounded depth so a pathological chain can never loop.
_resolve_instance_pid() {  # _resolve_instance_pid [start_pid]
  local p="${1:-$PPID}" comm depth=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$depth" -lt 16 ]; do
    comm=$(ps -o comm= -p "$p" 2>/dev/null | tr -d ' ')
    case "$comm" in claude|claude-code) printf '%s' "$p"; return 0;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    depth=$((depth + 1))
  done
  return 1
}

_repokey() {
  local common key
  common=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$common" 2>/dev/null && pwd -P) || return 1
  # md5sum (coreutils) preferred; cksum as a fallback so a missing md5sum never yields
  # an empty key (which would collapse every repo into one shared registry).
  key=$(printf '%s' "$common" | { md5sum 2>/dev/null || cksum; } | tr -cd '0-9a-f' | cut -c1-16)
  [ -n "$key" ] || return 1
  printf '%s' "$key"
}

REPOKEY=$(_repokey) || { echo "[coord] not inside a git repo." >&2; exit 1; }
ROOT="$COORD_HOME/$REPOKEY"
INSTANCES="$ROOT/instances.json"
CLAIMS="$ROOT/claims.json"
INBOX="$ROOT/inbox"
LOCK="$ROOT/lock"
COMMIT_LOCK="$ROOT/commit.lock"
GATE_LOCK="$ROOT/gate.lock"

# ---- Atomic init: mkdir is the create guard; never truncate an existing ledger. ----
cmd_init() {
  mkdir -p "$INBOX" 2>/dev/null
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    [ -s "$INSTANCES" ] || echo '{}' > "$INSTANCES"
    [ -s "$CLAIMS" ]    || echo '{}' > "$CLAIMS"
  ) 9>"$LOCK"
}

# write JSON atomically: jq into a temp file in the same dir, then mv (atomic rename)
_jq_write() {  # _jq_write <target-file> <jq-args...>
  local target="$1"; shift
  local tmp
  tmp=$(mktemp "${target}.XXXXXX") || return 1
  if jq "$@" "$target" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$target"
  else
    rm -f "$tmp"; return 1
  fi
}

# is instance <id> alive? Liveness = worktree-present AND (PID-alive OR heartbeat-fresh).
# PID-alive is a fast-path accelerator (a busy instance is instantly live); heartbeat-TTL
# is the authoritative fallback because on SDK/service harnesses the registered pid is an
# ephemeral hook shell that dies immediately — a PID-only check would reap every instance
# on the first reap pass. A removed worktree is an unconditional dead signal.
_alive() {  # _alive <id>
  local id="$1" pid trusted wt hb now
  pid=$(jq -r --arg i "$id" '.[$i].pid // empty' "$INSTANCES" 2>/dev/null)
  trusted=$(jq -r --arg i "$id" '.[$i].pid_trusted // false' "$INSTANCES" 2>/dev/null)
  wt=$(jq -r --arg i "$id" '.[$i].worktree // empty' "$INSTANCES" 2>/dev/null)
  [ -n "$pid" ] || return 1
  [ -z "$wt" ] || [ -d "$wt" ] || return 1          # worktree removed → dead
  # pid>0 guard FIRST: kill -0 0 hits the caller's process group and ALWAYS succeeds,
  # which would make a pid=0 (unresolved/sanitized) entry immortal. Treat <=0 as no pid.
  if [ "$pid" -gt 0 ] 2>/dev/null && kill -0 "$pid" 2>/dev/null; then
    return 0                                        # real process alive → live
  fi
  # pid is dead-or-unusable. If we TRUSTED the pid (resolved to the real claude process),
  # its death is authoritative → dead, reap now (no TTL wait). Only an UNtrusted pid
  # (resolution failed on this harness) falls back to heartbeat freshness.
  [ "$trusted" = "true" ] && return 1
  hb=$(jq -r --arg i "$id" '.[$i].heartbeat // 0' "$INSTANCES" 2>/dev/null)
  case "$hb" in ''|*[!0-9]*) hb=0;; esac
  now=$(_now)
  [ "$(( now - hb ))" -lt "$HEARTBEAT_TTL" ]        # fresh → live; stale → dead
}

# reap dead instances and free their claims (must be called inside the flock).
# Liveness model: a trusted (resolved-to-real-claude) pid is authoritative via kill -0;
# an untrusted pid falls back to heartbeat TTL. See _alive and the file header. A removed
# worktree is an unconditional dead signal. PID reuse (a recycled pid landing on an
# unrelated live process) is an accepted rare gap on a single host with 2-3 instances.
_reap_locked() {
  local id
  # instances.json is an untrusted boundary (an operator or bug could hand-edit a key with
  # whitespace/glob chars): read keys line-by-line so no word-splitting or glob expansion.
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! _alive "$id"; then
      _jq_write "$INSTANCES" --arg i "$id" 'del(.[$i])'
      _jq_write "$CLAIMS" --arg i "$id" 'with_entries(select(.value.by != $i))'
    fi
  done < <(jq -r 'keys[]' "$INSTANCES" 2>/dev/null)
  # Prune orphan claims: any claim whose holder is no longer a live registered instance.
  # CRITICAL: if instances.json is unparseable, ABORT the prune — never treat a parse
  # failure as "no live instances", which would silently wipe every claim.
  local live; live=$(jq -c 'keys' "$INSTANCES" 2>/dev/null) || return 0
  [ -n "$live" ] || return 0
  _jq_write "$CLAIMS" --argjson live "$live" 'with_entries(.value.by as $b | select($live | index($b)))'
}

cmd_register() {
  # The pid we store must be the LONG-LIVED instance process, not coord.sh's ephemeral
  # caller. We resolve it by walking up to the `claude` ancestor (_resolve_instance_pid);
  # that yields a session-long, per-instance, TRUSTED pid. An explicit --pid (e.g. from a
  # launcher that already knows the real pid) wins over resolution. If neither yields a
  # real ancestor we keep the given/PPID value but mark it UNtrusted, so _alive falls back
  # to the heartbeat TTL instead of trusting a pid that may be ephemeral.
  local id="" wt="" br="" role="" pid="" explicit=0
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; --worktree) wt="$2"; shift 2;;
    --branch) br="$2"; shift 2;; --role) role="$2"; shift 2;;
    --pid) pid="$2"; explicit=1; shift 2;; *) shift;;
  esac; done
  [ -n "$id" ] || { echo "[coord] register: --id required" >&2; return 2; }
  _valid_id "$id" || { echo "[coord] register: invalid --id '$id' (allowed: A-Za-z0-9._-)" >&2; return 2; }
  local trusted=false rpid
  if [ "$explicit" = 1 ]; then
    case "$pid" in ''|*[!0-9]*) echo "[coord] register: --pid must be numeric (got '$pid')" >&2; return 2;; esac
    trusted=true                                    # caller asserts a real pid
  elif rpid=$(_resolve_instance_pid "$PPID"); then
    pid="$rpid"; trusted=true                       # resolved to the real claude process
  else
    pid="$PPID"; trusted=false                      # no claude ancestor → TTL fallback
  fi
  cmd_init
  local rc=0
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    # Reap dead instances FIRST — otherwise a stale registry (peers that crashed or were
    # never deregistered) inflates the live count and trips the cap warning on phantoms.
    _reap_locked
    local already=0
    jq -e --arg i "$id" 'has($i)' "$INSTANCES" >/dev/null 2>&1 && already=1
    if ! _jq_write "$INSTANCES" --arg i "$id" --arg pid "$pid" --arg wt "$wt" \
      --arg br "$br" --arg role "$role" --arg tr "$trusted" --arg now "$(_now)" \
      '.[$i] = {pid:($pid|tonumber), pid_trusted:($tr=="true"), worktree:$wt, branch:$br, role:$role, started:($now|tonumber), heartbeat:($now|tonumber)}'; then
      # set -uo pipefail has NO -e: a write failure here (disk full, corrupt ledger JSON)
      # would otherwise fall through silently and cmd_register would return success while
      # the instance never actually made it into the ledger — it would run for the rest
      # of the session with no claims and off the roster, exactly the uncoordinated-
      # editing failure mode this file exists to prevent. Fail loudly instead.
      echo "[coord] register: failed to write instance ledger for '$id' (disk full? corrupt $INSTANCES?) — instance is NOT registered." >&2
      exit 8
    fi
    # The cap is advisory, never a rejection: a SessionStart hook cannot un-start a
    # session that is already running, and an instance that bailed out of registering
    # here because of a cap would run WITHOUT claims and OFF the roster — exactly the
    # uncoordinated-editing failure mode this whole substrate exists to prevent. So we
    # register unconditionally and instead warn loudly + return a distinct exit code, so
    # the caller (hook/operator) can decide to close a session or hold off on heavy
    # gates. Only warn on a genuinely NEW registration — re-registering an id already on
    # the roster (e.g. a heartbeat-triggered re-register) isn't a new instance.
    if [ "$already" -eq 0 ]; then
      local n; n=$(jq 'length' "$INSTANCES" 2>/dev/null || echo 0)
      if [ "$n" -gt "$MAX_INSTANCES" ]; then
        echo "[coord] WARNING: $n live instances now registered, over the cap of $MAX_INSTANCES (CLAUDE_SUBTEAMS_MAX_INSTANCES). Registration proceeds anyway — recommend closing an extra session, and avoid starting heavy gates (tsc+vitest+canary) until the count drops; they serialize on gate-lock and will queue behind each other." >&2
        # exit 6 = SUCCESS with a warning, NOT a failure — the write above already
        # succeeded and the instance IS on the roster. Every caller of `register`
        # (hooks, `&&` chains, `set -e` callers) MUST treat 6 as success; see the usage
        # header. Only exit 8 means the instance failed to register.
        exit 6
      fi
    fi
  ) 9>"$LOCK"
  rc=$?
  return "$rc"
}

cmd_deregister() {
  local id=""; [ "${1:-}" = "--id" ] && id="${2:-}"
  [ -n "$id" ] || return 2
  _valid_id "$id" || { echo "[coord] deregister: invalid --id '$id'" >&2; return 2; }
  [ -f "$INSTANCES" ] || return 0
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    _jq_write "$INSTANCES" --arg i "$id" 'del(.[$i])'
    _jq_write "$CLAIMS" --arg i "$id" 'with_entries(select(.value.by != $i))'
  ) 9>"$LOCK"
  # Also remove the quarantine file (see recv) — otherwise it's a slow, unbounded leak:
  # one file per session id that ever received a single malformed message, forever.
  rm -f "$INBOX/$id.jsonl" "$INBOX/$id.bad.jsonl" 2>/dev/null
}

cmd_heartbeat() {
  # Self-healing: an existing entry just gets its heartbeat bumped; a MISSING entry is
  # recreated (re-register), so an instance that was reaped or deregistered comes back on
  # its next activity instead of vanishing for the rest of the session. On recreation we
  # resolve the real claude pid exactly as cmd_register does (so the rebuilt entry is
  # pid_trusted and gets authoritative liveness, not a TTL guess). Note: a late async
  # heartbeat arriving just after SessionEnd can recreate a phantom entry; it holds no
  # claims (those were released) and is reaped once its real pid dies, so impact is at
  # most transient roster clutter.
  local id="" pid="" explicit=0 wt="" br=""
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; --pid) pid="$2"; explicit=1; shift 2;;
    --worktree) wt="$2"; shift 2;; --branch) br="$2"; shift 2;; *) shift;;
  esac; done
  [ -n "$id" ] || return 2
  _valid_id "$id" || { echo "[coord] heartbeat: invalid --id '$id'" >&2; return 2; }
  local trusted=false rpid
  if [ "$explicit" = 1 ] && printf '%s' "$pid" | grep -qE '^[0-9]+$'; then
    trusted=true
  elif rpid=$(_resolve_instance_pid "$PPID"); then
    pid="$rpid"; trusted=true
  else
    pid="$PPID"; trusted=false
  fi
  cmd_init
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    _jq_write "$INSTANCES" --arg i "$id" --arg pid "$pid" --arg wt "$wt" \
      --arg br "$br" --arg tr "$trusted" --arg now "$(_now)" \
      'if .[$i] then .[$i].heartbeat = ($now|tonumber)
       else .[$i] = {pid:($pid|tonumber), pid_trusted:($tr=="true"), worktree:$wt, branch:$br, role:"", started:($now|tonumber), heartbeat:($now|tonumber)} end'
  ) 9>"$LOCK"
}

cmd_roster() {
  [ -f "$INSTANCES" ] || { echo "(no instances)"; return 0; }
  # Reap AND read inside ONE locked section: a register/deregister landing between reap and
  # read would otherwise make the printed roster stale (autonomy-check.sh trusts this roster).
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    _reap_locked
    local n; n=$(jq 'length' "$INSTANCES" 2>/dev/null || echo 0)
    echo "Live instances ($n):"
    jq -r 'to_entries[] | "  - \(.key)  pid=\(.value.pid)  branch=\(.value.branch)  worktree=\(.value.worktree)"' "$INSTANCES" 2>/dev/null
  ) 9>"$LOCK"
}

cmd_reap() { cmd_init; ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }; _reap_locked ) 9>"$LOCK"; }

# Machine-readable live-instance count: reaps dead peers first (same as roster), then
# prints EXACTLY one bare integer to stdout and nothing else. Exists because an external
# consumer (another repo's git hook) previously parsed `roster`'s first line with a
# regex ("Live instances (N):") — fragile, since roster's prose is free to change. This
# output format IS the contract: never add surrounding text to it.
cmd_count() {
  cmd_init
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    _reap_locked
    local n; n=$(jq 'length' "$INSTANCES" 2>/dev/null)
    case "$n" in ''|*[!0-9]*) n=0;; esac
    echo "$n"
  ) 9>"$LOCK"
}

# atomic claim-or-reject, one or more paths per call. exit 0 = ALL claimed (by me/new);
# exit 3 = at least one held by another live instance (then NOTHING is claimed — all-or-nothing,
# so a partially-claimed batch can never masquerade as success).
cmd_claim() {
  local id=""; local -a paths=()
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; *) paths+=("$1"); shift;;
  esac; done
  [ -n "$id" ] && [ "${#paths[@]}" -gt 0 ] || { echo "[coord] claim: --id and at least one PATH required" >&2; return 2; }
  _valid_id "$id" || { echo "[coord] claim: invalid --id '$id'" >&2; return 2; }
  _valid_paths claim "${paths[@]}" || return 2
  cmd_init
  local plist
  plist=$(printf '%s\n' "${paths[@]}" | jq -R . | jq -sc .) || return 1
  local rc=0
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    _reap_locked
    # The claimant MUST be a currently-registered live instance, else the claim provides
    # no exclusion (orphan-prune would wipe it) — fail LOUDLY rather than silently void.
    if ! jq -e --arg i "$id" 'has($i)' "$INSTANCES" >/dev/null 2>&1; then
      echo "[coord] claim: instance '$id' is not registered (run register first)." >&2
      exit 4
    fi
    local conflicts
    conflicts=$(jq -r --argjson ps "$plist" --arg id "$id" \
      'to_entries[] | select(.key as $k | $ps | index($k)) | select(.value.by != $id)
       | "[coord] '\''\(.key)'\'' is claimed by '\''\(.value.by)'\'' — coordinate or wait."' \
      "$CLAIMS" 2>/dev/null)
    if [ -n "$conflicts" ]; then
      printf '%s\n' "$conflicts" >&2
      exit 3   # already held by another (reap already ran, so it's live)
    fi
    _jq_write "$CLAIMS" --argjson ps "$plist" --arg id "$id" --arg now "$(_now)" \
      'reduce $ps[] as $p (.; .[$p] = {by:$id, at:($now|tonumber)})'
  ) 9>"$LOCK"
  rc=$?
  return "$rc"
}

cmd_release() {
  local id="" all=0; local -a paths=()
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; --all) all=1; shift;; *) paths+=("$1"); shift;;
  esac; done
  [ -n "$id" ] || return 2
  [ -f "$CLAIMS" ] || return 0
  local plist=""
  if [ "$all" -ne 1 ]; then
    [ "${#paths[@]}" -gt 0 ] || return 2
    _valid_paths release "${paths[@]}" || return 2
    plist=$(printf '%s\n' "${paths[@]}" | jq -R . | jq -sc .) || return 1
  fi
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    if [ "$all" -eq 1 ]; then
      _jq_write "$CLAIMS" --arg i "$id" 'with_entries(select(.value.by != $i))'
    else
      _jq_write "$CLAIMS" --argjson ps "$plist" --arg i "$id" \
        'with_entries(select((.value.by == $i and (.key as $k | $ps | index($k))) | not))'
    fi
  ) 9>"$LOCK"
}

cmd_claims() {
  [ -f "$CLAIMS" ] || { echo "(no claims)"; return 0; }
  jq -r 'to_entries[] | "  - \(.key)  by=\(.value.by)"' "$CLAIMS" 2>/dev/null || echo "(no claims)"
}

# ---- Mailbox entry validation (hardening lesson from Anthropic's native agent-teams:
# before v2.1.207 one malformed inbox line blocked delivery on every tick until someone
# deleted it by hand — see the design doc's §0). A line is VALID iff it parses as JSON
# and has a string `.msg` field; blank/whitespace-only lines are not malformed, just
# ignored. `.from` is ALSO type-checked (must be absent/null or a string) — a numeric or
# object `.from` used to classify as ok:true and then blow up `.from|gsub(...)` in recv's
# renderer, a runtime jq error swallowed by 2>/dev/null that silently dropped the message
# instead of quarantining it (found by Codex cross-review). Shared by recv, recv --count,
# and notify-due so "how many messages are waiting" never disagrees with "how many
# messages recv actually delivers".
_MAILBOX_VALIDATE_JQ='
  . as $raw
  | if ($raw | test("^[ \t]*$")) then empty
    else
      ($raw | try fromjson catch null) as $obj
      | if ($obj != null and ($obj|type) == "object"
            and (($obj.msg? // null) | type) == "string"
            and (($obj.from? // null) == null or (($obj.from? // null) | type) == "string"))
        then {ok:true, at:($obj.at // 0), from:($obj.from // ""), msg:$obj.msg}
        else {ok:false, raw:$raw}
        end
    end
'

_mailbox_valid_count() {  # _mailbox_valid_count <box> — count of VALID lines only
  local box="$1" n
  [ -s "$box" ] || { echo 0; return 0; }
  n=$(jq -Rc "$_MAILBOX_VALIDATE_JQ" "$box" 2>/dev/null | jq -s 'map(select(.ok)) | length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0;; esac
  echo "$n"
}

_mailbox_bad_count() {  # _mailbox_bad_count <box> — count of MALFORMED lines only
  local box="$1" n
  [ -s "$box" ] || { echo 0; return 0; }
  n=$(jq -Rc "$_MAILBOX_VALIDATE_JQ" "$box" 2>/dev/null | jq -s 'map(select(.ok|not)) | length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0;; esac
  echo "$n"
}

cmd_send() {
  local from="" to="" msg=""
  while [ $# -gt 0 ]; do case "$1" in
    --from) from="$2"; shift 2;; --to) to="$2"; shift 2;; *) msg="$1"; shift;;
  esac; done
  [ -n "$to" ] && [ -n "$msg" ] || { echo "[coord] send: --to and MSG required" >&2; return 2; }
  _valid_id "$to" || { echo "[coord] send: invalid --to '$to'" >&2; return 2; }
  [ -z "$from" ] || _valid_id "$from" || { echo "[coord] send: invalid --from '$from'" >&2; return 2; }
  cmd_init
  local line
  line=$(jq -nc --arg f "$from" --arg m "$msg" --arg now "$(_now)" '{from:$f, at:($now|tonumber), msg:$m}')
  # per-recipient inbox; flock the inbox file so concurrent senders don't interleave.
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    printf '%s\n' "$line" >> "$INBOX/$to.jsonl" ) 9>"$INBOX/$to.jsonl.lock"
}

cmd_recv() {
  # --count: print the number of unread, VALID messages WITHOUT clearing — a
  # non-destructive peek for the notify hook (which must never destroy messages it only
  # counts). Default mode prints all valid messages, quarantines malformed ones instead
  # of silently dropping them (see _MAILBOX_VALIDATE_JQ), and CLEARS the inbox (the
  # explicit, lossless-for-valid-messages consume the operator or orchestrator runs on
  # purpose). Newlines in from/msg are collapsed on render so one stored message is
  # always one line — a peer cannot forge a fake "from:" header by embedding a newline
  # in its message body.
  local id="" count=0
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; --count) count=1; shift;; *) shift;;
  esac; done
  [ -n "$id" ] || return 2
  _valid_id "$id" || { echo "[coord] recv: invalid --id '$id'" >&2; return 2; }
  local box="$INBOX/$id.jsonl"
  if [ "$count" = 1 ]; then
    _mailbox_valid_count "$box"
    return 0
  fi
  [ -f "$box" ] || { echo "(no messages)"; return 0; }
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    if [ -s "$box" ]; then
      local classified valid_out bad_lines bad_n quarantine _qtmp
      if ! classified=$(jq -Rc "$_MAILBOX_VALIDATE_JQ" "$box" 2>/dev/null); then
        # jq failing on the WHOLE classification pass (incompatible jq version, OOM on a
        # huge line, corrupt binary) is different from a single malformed LINE — that
        # case is handled below via .ok=false and quarantined. A pass-level failure must
        # NOT fall through to ": > $box" below: an empty $classified would print "(no
        # messages)" and then the clear would silently destroy every VALID, unread
        # message in the box. Leave the box untouched and fail loudly instead.
        echo "[coord] recv: jq failed to classify inbox for '$id' (nonzero exit) — inbox left UNTOUCHED, nothing cleared. Check the jq binary/version." >&2
        exit 9
      fi
      valid_out=$(printf '%s\n' "$classified" | jq -r 'select(.ok) | "  [\(.at)] from \(.from|gsub("\n";" ")): \(.msg|gsub("\n";"\\n"))"' 2>/dev/null)
      bad_lines=$(printf '%s\n' "$classified" | jq -r 'select(.ok|not) | .raw' 2>/dev/null)
      if [ -n "$valid_out" ]; then
        printf '%s\n' "$valid_out"
      else
        echo "(no messages)"
      fi
      if [ -n "$bad_lines" ]; then
        # A malformed line must never just vanish (that's the Anthropic mailbox lesson):
        # quarantine it where an operator can inspect it, and say so loudly. The append
        # must SUCCEED before we're allowed to clear $box below (Codex cross-review
        # finding): a failed quarantine write (disk full) falling through to the clear
        # anyway would turn "couldn't quarantine" into "silently lost the bad entries",
        # exactly the loss this whole mechanism exists to prevent.
        bad_n=$(printf '%s\n' "$bad_lines" | grep -c '.')
        quarantine="$INBOX/$id.bad.jsonl"
        if ! printf '%s\n' "$bad_lines" >> "$quarantine"; then
          echo "[coord] recv: FAILED to write $bad_n malformed entries to quarantine '$quarantine' (disk full?) — inbox left UNTOUCHED, nothing cleared." >&2
          exit 9
        fi
        # Cap growth: a repeatedly-misbehaving sender must not turn this into an
        # unbounded log — keep only the most recent 200 quarantined lines. A unique
        # mktemp path (not a fixed "$quarantine.tmp") avoids colliding with a leftover or
        # concurrent trim of the same name. Trim failure is non-fatal and does NOT block
        # the box clear below — the malformed lines are already safely appended above
        # either way, so at worst the quarantine file just stays untrimmed (a nuisance,
        # not data loss).
        _qtmp=$(mktemp "${quarantine}.XXXXXX" 2>/dev/null) && {
          tail -n 200 "$quarantine" > "$_qtmp" 2>/dev/null && mv -f "$_qtmp" "$quarantine" || rm -f "$_qtmp" 2>/dev/null
        }
        echo "[coord] recv: dropped $bad_n malformed inbox entries → quarantined in $quarantine" >&2
      fi
      : > "$box"   # clear after reading (valid messages consumed, bad ones quarantined)
    else
      echo "(no messages)"
    fi
  ) 9>"$INBOX/$id.jsonl.lock"
}

cmd_commit_lock() {
  # Lock ORDER (see gate-lock below): commit-lock is always the INNER lock — a CMD run
  # here may itself be nested inside gate-lock, but must never itself take gate-lock.
  # Commits are short, gates are long; the opposite nesting would let two instances
  # ABBA-deadlock by acquiring the two locks in opposite order.
  [ "${1:-}" = "--" ] && shift
  [ $# -gt 0 ] || { echo "[coord] commit-lock: expected -- CMD..." >&2; return 2; }
  cmd_init
  # 9>&- on CMD: close the lock fd for CMD (and thus its children) before running it —
  # same fd-leak fix as gate-lock (see there for the full rationale). A backgrounded
  # descendant spawned by a commit hook would otherwise inherit fd 9 and hold the lock
  # after we return; the subshell itself still holds and releases the lock normally.
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }; "$@" 9>&- ) 9>"$COMMIT_LOCK"
}

cmd_gate_lock() {
  # Serializes HEAVY per-instance gates (tsc + vitest + canary boot against a DB copy)
  # onto a SEPARATE lock from commit-lock: a gate takes minutes, a commit takes
  # milliseconds — sharing one lock would let a long gate block every fast, unrelated
  # commit queued behind it. See the design doc §5.2/§7: this is the main guard that
  # makes running 4-5 instances safe on a 6 vCPU / 12 GB box (their gates would
  # otherwise run concurrently and starve each other for CPU/RAM).
  #
  # Lock ORDER (avoids an ABBA deadlock with commit-lock): gate-lock is always taken
  # OUTSIDE commit-lock, never the other way around — i.e. a CMD run under gate-lock may
  # itself take commit-lock, but a CMD run under commit-lock must never take gate-lock.
  # Gates are long, commits are short; nesting the long lock inside the short one would
  # let two instances deadlock by acquiring the two locks in opposite order. Shell has no
  # way to enforce this mechanically — it is a convention every caller must honor.
  local timeout=""
  while [ "${1:-}" != "--" ] && [ $# -gt 0 ]; do
    case "$1" in
      --timeout)
        # set -u is active: with only 1 arg left ("--timeout" itself, no value), a bare
        # "$2" here is an unbound-variable reference and aborts the whole script instead
        # of giving usage + rc=2. Check argument count BEFORE touching $2 — and also
        # reject "$2" == "--", the "gate-lock --timeout -- CMD..." case where a value was
        # simply omitted and "--" (the CMD separator) would otherwise be swallowed as if
        # it were the timeout, silently misparsing the rest of the command line.
        if [ $# -lt 2 ] || [ "$2" = "--" ]; then
          echo "[coord] gate-lock: --timeout requires a value" >&2
          return 2
        fi
        timeout="$2"; shift 2;;
      *) echo "[coord] gate-lock: unexpected argument '$1' (expected [--timeout N] -- CMD...)" >&2; return 2;;
    esac
  done
  [ "${1:-}" = "--" ] && shift
  [ $# -gt 0 ] || { echo "[coord] gate-lock: expected [--timeout N] -- CMD..." >&2; return 2; }
  if [ -n "$timeout" ]; then
    case "$timeout" in ''|*[!0-9]*) echo "[coord] gate-lock: --timeout must be a non-negative integer (got '$timeout')" >&2; return 2;; esac
  fi
  cmd_init
  local rc
  if [ -n "$timeout" ]; then
    # 75, not 7: CMD's own exit code is always passed through on success, so a small
    # integer like 7 is too easy to collide with — the caller couldn't tell "gate-lock
    # itself timed out" apart from "CMD ran and legitimately returned 7". 75 sits outside
    # the range typical CMD exit codes use.
    ( flock -w "$timeout" 9 || { echo "[coord] gate-lock: timed out after ${timeout}s waiting for the gate lock (another instance's gate is running)." >&2; exit 75; }
      # 9>&- on CMD: close the lock fd for CMD (and thus its children) before running it.
      # A backgrounded/daemonized descendant of CMD (a gate spawns a canary boot process)
      # would otherwise INHERIT fd 9 and keep the flock held after gate-lock returns —
      # the parent subshell itself still holds and releases the lock normally on exit.
      "$@" 9>&-
    ) 9>"$GATE_LOCK"
    rc=$?
  else
    # No timeout by default: a gate runs for minutes and a queue of up to
    # MAX_INSTANCES instances waiting their turn is expected, not exceptional — a
    # spurious timeout would fail a perfectly healthy gate for no reason other than bad
    # luck in the queue, which is worse than just waiting.
    ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
      "$@" 9>&-
    ) 9>"$GATE_LOCK"
    rc=$?
  fi
  return "$rc"
}

cmd_notify_due() {
  # Throttled notification check for HIGH-FREQUENCY events (PostToolUse): echo the unread
  # count IFF a message has arrived since this id was last notified — then advance the
  # marker — else echo 0. This yields exactly ONE notice per newly-arrived message instead
  # of one per tool call. Non-destructive: it never clears the inbox (recv stays the
  # explicit consume). The marker is keyed by the newest message's `at` timestamp.
  local id=""
  while [ $# -gt 0 ]; do case "$1" in --id) id="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || return 2
  _valid_id "$id" || { echo "[coord] notify-due: invalid --id '$id'" >&2; return 2; }
  local box="$INBOX/$id.jsonl"
  [ -s "$box" ] || { echo 0; return 0; }
  cmd_init
  # Lock the SAME per-inbox file send/recv use (not $LOCK): notify-due reads this id's inbox,
  # so it must be mutually exclusive with a send appending to it / a recv clearing it. Only
  # this single inbox is touched, so there is no multi-lock ordering / deadlock concern.
  ( flock 9 || { echo "coord: failed to acquire lock" >&2; exit 5; }
    mkdir -p "$ROOT/notify" 2>/dev/null
    local marker="$ROOT/notify/$id.last" newest last count bad_n badmarker bad_last
    # "newest" and "count" must both be computed from VALID entries only — otherwise a
    # malformed line could still advance the throttle marker (silently swallowing the
    # next real notification) while never counting toward the number reported.
    newest=$(jq -Rc "$_MAILBOX_VALIDATE_JQ" "$box" 2>/dev/null | jq -r 'select(.ok) | .at' 2>/dev/null | sort -n | tail -1)
    case "$newest" in ''|*[!0-9]*) newest=0;; esac
    last=0; [ -f "$marker" ] && last=$(cat "$marker" 2>/dev/null)
    case "$last" in ''|*[!0-9]*) last=0;; esac
    # Bad-entry warning is throttled to ONCE per distinct count, via its own marker file —
    # this hook fires on every PostToolUse, so an unthrottled warning on a mailbox that's
    # entirely malformed (valid count stays 0 forever, so it's never cleared by recv)
    # would otherwise print on every single tool call, forever.
    bad_n=$(_mailbox_bad_count "$box")
    badmarker="$ROOT/notify/$id.badwarn"
    if [ "$bad_n" -gt 0 ]; then
      bad_last=0; [ -f "$badmarker" ] && bad_last=$(cat "$badmarker" 2>/dev/null)
      case "$bad_last" in ''|*[!0-9]*) bad_last=0;; esac
      if [ "$bad_n" -ne "$bad_last" ]; then
        echo "[coord] notify-due: $bad_n malformed inbox entries pending — run 'coord.sh recv --id $id' to quarantine them" >&2
        printf '%s' "$bad_n" > "$badmarker"
      fi
    else
      rm -f "$badmarker" 2>/dev/null   # mailbox clean again — reset so a future recurrence re-warns
    fi
    if [ "$newest" -gt "$last" ]; then
      printf '%s' "$newest" > "$marker"
      count=$(_mailbox_valid_count "$box")
      echo "$count"
    else
      echo 0
    fi
  ) 9>"$INBOX/$id.jsonl.lock"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    init) cmd_init;;
    register) cmd_register "$@";;
    deregister) cmd_deregister "$@";;
    heartbeat) cmd_heartbeat "$@";;
    roster) cmd_roster;;
    reap) cmd_reap;;
    count) cmd_count;;
    claim) cmd_claim "$@";;
    release) cmd_release "$@";;
    claims) cmd_claims;;
    send) cmd_send "$@";;
    recv) cmd_recv "$@";;
    notify-due) cmd_notify_due "$@";;
    commit-lock) cmd_commit_lock "$@";;
    gate-lock) cmd_gate_lock "$@";;
    repokey) echo "$REPOKEY  ($ROOT)";;
    ""|-h|--help) sed -n '2,64p' "$0";;
    *) echo "[coord] unknown command: $cmd" >&2; return 2;;
  esac
}

main "$@"
