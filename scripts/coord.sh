#!/bin/bash
# coord.sh — portable multi-instance coordination for claude-subteams.
#
# A small, file-based substrate (flock + jq JSON + per-instance inbox) so 2-3 identical
# Claude Code instances on ONE machine, working ONE git repo (each in its own worktree),
# can coordinate WITHOUT depending on Claude Code's native agent-teams. Opt-in only.
#
# Activation: nothing here does anything unless CLAUDE_SUBTEAMS_MULTI_INSTANCE=1.
# Liveness is authoritative by PID (kill -0) on this single host; heartbeat TTL and a
# missing worktree are only secondary reap signals. Claims are ADVISORY (cooperating
# instances honor them) — this is coordination, not OS-enforced locking.
#
# Layout (shared across all worktrees of one repo, keyed by --git-common-dir):
#   $COORD_HOME/<repokey>/
#     instances.json   { id: {pid, worktree, branch, role, started, heartbeat} }
#     claims.json      { "relpath": {by, at} }
#     inbox/<id>.jsonl  append-only messages for <id>
#     lock              flock target for instances/claims read-modify-write
#     commit.lock       flock target for serialized git commits
#
# Usage: coord.sh <command> [args]
#   init                               ensure coord dir + files exist (atomic)
#   register  --id ID [--worktree P --branch B --role R]
#   deregister --id ID                 remove instance + release its claims
#   heartbeat --id ID                  refresh liveness timestamp
#   roster                             list live instances (reaps dead first)
#   reap                               remove dead instances + release their claims
#   claim     --id ID PATH             atomic claim-or-reject (exit 0 ok, 3 rejected)
#   release   --id ID [PATH | --all]   release one or all of an instance's claims
#   claims                             list current claims
#   send      --from ID --to ID MSG    append MSG to recipient inbox
#   recv      --id ID                  print + clear own inbox
#   commit-lock -- CMD...              run CMD holding the global commit lock
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

_now() { date +%s; }

# Identity sanity: ids and inbox targets become filenames and jq keys — reject anything
# that could traverse the coord dir or break the ledger. Session-hash ids are [a-f0-9].
_valid_id() { printf '%s' "${1:-}" | grep -qE '^[A-Za-z0-9._-]+$'; }

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

# ---- Atomic init: mkdir is the create guard; never truncate an existing ledger. ----
cmd_init() {
  mkdir -p "$INBOX" 2>/dev/null
  ( flock 9
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

# is instance <id> alive? PID exists (authoritative) AND its worktree still exists.
_alive() {  # _alive <id>
  local id="$1" pid wt
  pid=$(jq -r --arg i "$id" '.[$i].pid // empty' "$INSTANCES" 2>/dev/null)
  wt=$(jq -r --arg i "$id" '.[$i].worktree // empty' "$INSTANCES" 2>/dev/null)
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1            # PID gone → dead
  [ -z "$wt" ] || [ -d "$wt" ] || return 1          # worktree removed → dead
  return 0
}

# reap dead instances and free their claims (must be called inside the flock).
# Liveness is authoritative by PID (+ worktree existence) on this single host — a
# PID-alive instance is NEVER reaped on a stale heartbeat (a real instance can be quiet
# for a long tool call). Heartbeat is recorded for observability; PID reuse is an
# accepted rare gap on a single host with 2-3 long-lived instances.
_reap_locked() {
  local ids id
  ids=$(jq -r 'keys[]' "$INSTANCES" 2>/dev/null)
  for id in $ids; do
    if ! _alive "$id"; then
      _jq_write "$INSTANCES" --arg i "$id" 'del(.[$i])'
      _jq_write "$CLAIMS" --arg i "$id" 'with_entries(select(.value.by != $i))'
    fi
  done
  # Prune orphan claims: any claim whose holder is no longer a live registered instance.
  # CRITICAL: if instances.json is unparseable, ABORT the prune — never treat a parse
  # failure as "no live instances", which would silently wipe every claim.
  local live; live=$(jq -c 'keys' "$INSTANCES" 2>/dev/null) || return 0
  [ -n "$live" ] || return 0
  _jq_write "$CLAIMS" --argjson live "$live" 'with_entries(.value.by as $b | select($live | index($b)))'
}

cmd_register() {
  # --pid is the LONG-LIVED instance process to check liveness against (the Claude
  # process), NOT coord.sh's own ephemeral pid. Defaults to $PPID (the hook/shell that
  # invoked us — closer to the instance than $$). Heartbeat TTL is the reliable backstop
  # when the captured pid is not the true instance pid.
  local id="" wt="" br="" role="" pid="$PPID"
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; --worktree) wt="$2"; shift 2;;
    --branch) br="$2"; shift 2;; --role) role="$2"; shift 2;;
    --pid) pid="$2"; shift 2;; *) shift;;
  esac; done
  [ -n "$id" ] || { echo "[coord] register: --id required" >&2; return 2; }
  _valid_id "$id" || { echo "[coord] register: invalid --id '$id' (allowed: A-Za-z0-9._-)" >&2; return 2; }
  case "$pid" in ''|*[!0-9]*) echo "[coord] register: --pid must be numeric (got '$pid')" >&2; return 2;; esac
  cmd_init
  ( flock 9
    _jq_write "$INSTANCES" --arg i "$id" --arg pid "$pid" --arg wt "$wt" \
      --arg br "$br" --arg role "$role" --arg now "$(_now)" \
      '.[$i] = {pid:($pid|tonumber), worktree:$wt, branch:$br, role:$role, started:($now|tonumber), heartbeat:($now|tonumber)}'
  ) 9>"$LOCK"
}

cmd_deregister() {
  local id=""; [ "${1:-}" = "--id" ] && id="${2:-}"
  [ -n "$id" ] || return 2
  [ -f "$INSTANCES" ] || return 0
  ( flock 9
    _jq_write "$INSTANCES" --arg i "$id" 'del(.[$i])'
    _jq_write "$CLAIMS" --arg i "$id" 'with_entries(select(.value.by != $i))'
  ) 9>"$LOCK"
  rm -f "$INBOX/$id.jsonl" 2>/dev/null
}

cmd_heartbeat() {
  local id=""; [ "${1:-}" = "--id" ] && id="${2:-}"
  [ -n "$id" ] || return 2
  [ -f "$INSTANCES" ] || return 0
  ( flock 9
    _jq_write "$INSTANCES" --arg i "$id" --arg now "$(_now)" \
      'if .[$i] then .[$i].heartbeat = ($now|tonumber) else . end'
  ) 9>"$LOCK"
}

cmd_roster() {
  [ -f "$INSTANCES" ] || { echo "(no instances)"; return 0; }
  ( flock 9; _reap_locked ) 9>"$LOCK"
  local n; n=$(jq 'length' "$INSTANCES" 2>/dev/null || echo 0)
  echo "Live instances ($n):"
  jq -r 'to_entries[] | "  - \(.key)  pid=\(.value.pid)  branch=\(.value.branch)  worktree=\(.value.worktree)"' "$INSTANCES" 2>/dev/null
}

cmd_reap() { cmd_init; ( flock 9; _reap_locked ) 9>"$LOCK"; }

# atomic claim-or-reject. exit 0 = claimed (by me/new); exit 3 = held by another live instance.
cmd_claim() {
  local id="" path=""
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; *) path="$1"; shift;;
  esac; done
  [ -n "$id" ] && [ -n "$path" ] || { echo "[coord] claim: --id and PATH required" >&2; return 2; }
  _valid_id "$id" || { echo "[coord] claim: invalid --id '$id'" >&2; return 2; }
  cmd_init
  local rc=0
  ( flock 9
    _reap_locked
    # The claimant MUST be a currently-registered live instance, else the claim provides
    # no exclusion (orphan-prune would wipe it) — fail LOUDLY rather than silently void.
    if ! jq -e --arg i "$id" 'has($i)' "$INSTANCES" >/dev/null 2>&1; then
      echo "[coord] claim: instance '$id' is not registered (run register first)." >&2
      exit 4
    fi
    local by; by=$(jq -r --arg p "$path" '.[$p].by // empty' "$CLAIMS" 2>/dev/null)
    if [ -n "$by" ] && [ "$by" != "$id" ]; then
      exit 3   # already held by another (reap already ran, so it's live)
    fi
    _jq_write "$CLAIMS" --arg p "$path" --arg id "$id" --arg now "$(_now)" \
      '.[$p] = {by:$id, at:($now|tonumber)}'
  ) 9>"$LOCK"
  rc=$?
  if [ "$rc" -eq 3 ]; then
    local holder; holder=$(jq -r --arg p "$path" '.[$p].by // "?"' "$CLAIMS" 2>/dev/null)
    echo "[coord] '$path' is claimed by '$holder' — coordinate or wait." >&2
  fi
  return "$rc"
}

cmd_release() {
  local id="" path="" all=0
  while [ $# -gt 0 ]; do case "$1" in
    --id) id="$2"; shift 2;; --all) all=1; shift;; *) path="$1"; shift;;
  esac; done
  [ -n "$id" ] || return 2
  [ -f "$CLAIMS" ] || return 0
  ( flock 9
    if [ "$all" -eq 1 ]; then
      _jq_write "$CLAIMS" --arg i "$id" 'with_entries(select(.value.by != $i))'
    else
      [ -n "$path" ] || exit 2
      _jq_write "$CLAIMS" --arg p "$path" --arg i "$id" \
        'if .[$p].by == $i then del(.[$p]) else . end'
    fi
  ) 9>"$LOCK"
}

cmd_claims() {
  [ -f "$CLAIMS" ] || { echo "(no claims)"; return 0; }
  jq -r 'to_entries[] | "  - \(.key)  by=\(.value.by)"' "$CLAIMS" 2>/dev/null || echo "(no claims)"
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
  ( flock 9; printf '%s\n' "$line" >> "$INBOX/$to.jsonl" ) 9>"$INBOX/$to.jsonl.lock"
}

cmd_recv() {
  local id=""; [ "${1:-}" = "--id" ] && id="${2:-}"
  [ -n "$id" ] || return 2
  _valid_id "$id" || { echo "[coord] recv: invalid --id '$id'" >&2; return 2; }
  local box="$INBOX/$id.jsonl"
  [ -f "$box" ] || { echo "(no messages)"; return 0; }
  ( flock 9
    if [ -s "$box" ]; then
      # Tolerant parse: `fromjson?` skips any malformed line instead of aborting the
      # whole read (a single bad line must not silently swallow the rest of the inbox).
      jq -rR 'fromjson? | "  [\(.at)] from \(.from): \(.msg)"' "$box" 2>/dev/null
      : > "$box"   # clear after reading
    else
      echo "(no messages)"
    fi
  ) 9>"$INBOX/$id.jsonl.lock"
}

cmd_commit_lock() {
  [ "${1:-}" = "--" ] && shift
  [ $# -gt 0 ] || { echo "[coord] commit-lock: expected -- CMD..." >&2; return 2; }
  cmd_init
  ( flock 9; "$@" ) 9>"$COMMIT_LOCK"
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
    claim) cmd_claim "$@";;
    release) cmd_release "$@";;
    claims) cmd_claims;;
    send) cmd_send "$@";;
    recv) cmd_recv "$@";;
    commit-lock) cmd_commit_lock "$@";;
    repokey) echo "$REPOKEY  ($ROOT)";;
    ""|-h|--help) sed -n '2,40p' "$0";;
    *) echo "[coord] unknown command: $cmd" >&2; return 2;;
  esac
}

main "$@"
