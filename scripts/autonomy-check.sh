#!/bin/bash
# autonomy-check.sh — deterministic scope/cap gate for Tier 2 "bounded autonomous
# execution" (see the Autonomy Mode section of the living-plan skill). Evaluates the
# active run record embedded in docs/plans/active/IMPL-PLAN-*.md (between the
# `<!-- autonomy-run:begin/end -->` markers, schema pinned in IMPL-PLAN P1) and
# decides whether the current working tree is still inside its granted scope/caps.
#
# Usage: bash scripts/autonomy-check.sh [project-dir] [--checkpoint] [--session=<id>] [--pending=<path>]
#   project-dir   defaults to current directory (.)
#   --checkpoint  on exit 0 ONLY: append a script-authored AUTONOMY_CHECKPOINT line
#                 to the record — an AUDIT line for the operator's post-hoc review.
#                 Nothing in this script consumes it for enforcement math. Without
#                 this flag the script is entirely read-only.
#   --session=ID  caller session id (hooks pass it from stdin JSON). When provided,
#                 it must match the record's AUTONOMY_SESSION — a mismatch means a
#                 different session is reusing an old grant (exit 4). CLI calls
#                 without it skip the check (evidence mode).
#   --pending=P   a not-yet-written path to fold into the changed-file set BEFORE
#                 scope evaluation (pre-hoc: the hooks/autonomy-gate hook passes the
#                 target of an about-to-run Edit/Write/MultiEdit/NotebookEdit here so
#                 an out-of-scope write is caught before it lands). Read-only — this
#                 flag never writes anything; it only widens the set of paths checked
#                 against AUTONOMY_SCOPE. Bash has no reliable single target, so the
#                 caller never passes --pending for Bash — that stays post-hoc only
#                 (the autonomy-gate hook does a separate, best-effort pattern-match
#                 on the Bash command text for record-write detection — see the
#                 hook's own header comment; that is NOT this flag).
#
# G1 (path canonicalization): --pending is resolved with `_canon_path` (realpath -m,
# GNU; readlink -f fallback; raw-string degrade if neither exists) BEFORE it is
# relativized against the repo root, so a relative path or a `../` round-trip cannot
# dodge scope or falsely collide with the record-file exemption. The record file's
# own path (RECORD_REL) is resolved through the identical pipeline for the same
# reason. A --pending path whose resolved form lands outside the repo root is
# rejected outright as out-of-scope (exit 2) rather than left to an incidental glob
# mismatch.
#
# Deps: git, grep, awk ONLY (no jq — must run in every plugin-consumer repo without
# imposing a new dependency).
#
# Scope glob semantics: bash case-patterns — `*` crosses `/`, so `src/*` matches the
# WHOLE subtree (recursive), not just direct children. Write scopes accordingly.
# The active record file itself is auto-exempt from scope (script-managed).
#
# Caps are TOTAL-RUN caps, cumulative from AUTONOMY_BASE_COMMIT — every call
# recomputes them fresh from git (diff + untracked), never from a running counter.
# AUTONOMY_CHECKPOINT lines are audit-only evidence appended by this script; an
# agent deleting them cannot reset any cap, because nothing derives caps from them.
#
# Record schema is strict one-key-per-line (no packed multi-key lines, no trailing
# inline comments) — a record author trying to smuggle extra keys onto a free-text
# line (e.g. inside AUTONOMY_GRANT) cannot forge a later field, and a packed caps
# line simply fails the numeric check below (fails closed, never silently parsed).
#
# Exit 0 — proceed: env set, exactly one fresh record found, in scope, under caps.
# Exit 1 — usage error (bad arguments).
# Exit 2 — VIOLATION (operator-decision-required): an out-of-scope path, or a
#          total-run cap exceeded. The offending path(s)/numbers are printed.
# Exit 3 — CLAUDE_SUBTEAMS_AUTONOMY is unset: autonomy mode is not active. This is
#          the normal manual-mode result, not an error.
# Exit 4 — CANNOT EVALUATE (fail-closed, distinct from a violation): zero or more
#          than one active record, a record missing its end marker, missing/
#          unparseable/non-numeric fields, expired grant, session mismatch, an
#          unsafe base-commit value, base commit unresolvable, not a git repo, an
#          oversized record file, or (multi-instance mode) another live instance is
#          present — single-writer required for autonomy.
#
# ALL non-zero exit codes mean STOP — callers (notably hooks/autonomy-gate) must
# treat 1/2/3/4 identically as "do not proceed automatically".

set -uo pipefail

MAX_RECORD_BYTES=1048576   # 1 MB — DoS guard (C11): never parse a bigger plan file.

msg() { echo "[autonomy-check] $*"; }
usage_err() {
  echo "[autonomy-check] Usage: bash scripts/autonomy-check.sh [project-dir] [--checkpoint] [--session=<id>] [--pending=<path>]" >&2
  exit 1
}

# G1: canonicalize a path — realpath -m (GNU, tolerates missing components,
# resolves symlinks and `../`) preferred; readlink -f fallback if realpath is
# absent; if neither binary exists, OR the resolution call itself fails/produces
# no output, degrade to the raw string as-is (documented, best-effort-only branch —
# see the header comment for the same tradeoff hooks/autonomy-gate accepts).
_canon_path() { # path -> canonicalized path, or the raw string if resolution fails
  local p="$1" out=""
  [ -n "$p" ] || { printf '%s' ''; return; }
  if command -v realpath >/dev/null 2>&1; then
    out=$(realpath -m -- "$p" 2>/dev/null)
  elif command -v readlink >/dev/null 2>&1; then
    out=$(readlink -f -- "$p" 2>/dev/null)
  fi
  printf '%s' "${out:-$p}"
}

PROJECT_DIR="."
CHECKPOINT=0
CALLER_SESSION=""
PENDING_PATH=""
POSITIONAL_SEEN=0
for arg in "$@"; do
  case "$arg" in
    --checkpoint) CHECKPOINT=1 ;;
    --session=*) CALLER_SESSION="${arg#--session=}" ;;
    --pending=*) PENDING_PATH="${arg#--pending=}" ;;
    -*) usage_err ;;
    *)
      [ "$POSITIONAL_SEEN" -eq 0 ] || usage_err
      PROJECT_DIR="$arg"
      POSITIONAL_SEEN=1
      ;;
  esac
done

# 1. Env gate — FIRST, before any other work.
if [ -z "${CLAUDE_SUBTEAMS_AUTONOMY:-}" ]; then
  msg "CLAUDE_SUBTEAMS_AUTONOMY is unset — autonomy mode is not active."
  exit 3
fi

# 2. Confirm it's a git repo, then resolve to the repo TOP-LEVEL (C9). docs/plans/
# active/ lives at the repo root; if the caller's cwd is a subdirectory, using it
# verbatim would make the active-plan scan (and every git call below) silently miss
# the real state instead of failing loudly.
if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  msg "$PROJECT_DIR is not a git repository — cannot evaluate."
  exit 4
fi
REPO_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  msg "$PROJECT_DIR: could not resolve the repository top-level — cannot evaluate."
  exit 4
fi
PROJECT_DIR="$REPO_ROOT"
# G1: canonical form of the repo root, used as the comparison basis for --pending
# and the record-file exemption below — both must be relativized against the SAME
# resolved root, or a symlinked/relative repo path could desync the two.
PROJECT_DIR_CANON=$(_canon_path "$PROJECT_DIR")

# 3. Locate the run record: exactly one active IMPL-PLAN carrying a record block.
# Oversized candidates are skipped WITHOUT being grep'd (DoS guard, C11).
ACTIVE_DIR="${PROJECT_DIR}/docs/plans/active"
CANDIDATES=()
if [ -d "$ACTIVE_DIR" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    FSIZE=$(wc -c < "$f" 2>/dev/null || echo 0)
    if [ "$FSIZE" -gt "$MAX_RECORD_BYTES" ]; then
      msg "$f exceeds ${MAX_RECORD_BYTES} bytes — skipping without parsing (DoS guard)."
      continue
    fi
    grep -qF -- '<!-- autonomy-run:begin -->' "$f" 2>/dev/null && CANDIDATES+=("$f")
  done < <(find "$ACTIVE_DIR" -maxdepth 1 -type f -name 'IMPL-PLAN-*.md' 2>/dev/null || true)
fi
if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  msg "no active autonomy run record found under $ACTIVE_DIR — cannot evaluate."
  exit 4
fi
if [ "${#CANDIDATES[@]}" -gt 1 ]; then
  msg "${#CANDIDATES[@]} active autonomy run records found — ambiguous, cannot evaluate."
  exit 4
fi
RECORD_FILE="${CANDIDATES[0]}"

# 4. Both markers must be present (C2) — a begin with no end is an unterminated,
# unevaluable record, not "no record".
if ! grep -qF -- '<!-- autonomy-run:end -->' "$RECORD_FILE" 2>/dev/null; then
  msg "run record in $RECORD_FILE has a begin marker but no end marker — cannot evaluate."
  exit 4
fi

# 5. Extract the record block between the markers. Strict one-key-per-line (C1):
# no splitter, no trailing-comment stripper. A packed/malformed line simply fails
# the numeric or required-field checks below — fails closed, never silently parsed.
RECORD=$(awk '/<!-- autonomy-run:begin -->/{f=1;next} /<!-- autonomy-run:end -->/{f=0} f' "$RECORD_FILE")
if [ -z "$RECORD" ]; then
  msg "run record markers present in $RECORD_FILE but the block is empty — cannot evaluate."
  exit 4
fi

# First-match, prefix-anchored on "KEY: " (rejoins the value if it itself contains ": ").
_field() {
  printf '%s\n' "$RECORD" | awk -F': ' -v k="$1" '
    $1==k { out=$2; for(i=3;i<=NF;i++) out=out ": " $i; print out; exit }'
}

AUTONOMY_SCOPE=$(_field AUTONOMY_SCOPE)
AUTONOMY_BASE_COMMIT=$(_field AUTONOMY_BASE_COMMIT)
AUTONOMY_SESSION=$(_field AUTONOMY_SESSION)
AUTONOMY_EXPIRES_EPOCH=$(_field AUTONOMY_EXPIRES_EPOCH)
AUTONOMY_MAX_FILES=$(_field AUTONOMY_MAX_FILES)
AUTONOMY_MAX_LINES=$(_field AUTONOMY_MAX_LINES)

# 6. Required fields (C6 adds AUTONOMY_SESSION to the guard — a record with no
# session can never be evaluated, closing the "supply no --session to skip the
# match check" gap at the source).
if [ -z "$AUTONOMY_SCOPE" ] || [ -z "$AUTONOMY_BASE_COMMIT" ] || [ -z "$AUTONOMY_EXPIRES_EPOCH" ] || [ -z "$AUTONOMY_SESSION" ]; then
  msg "run record in $RECORD_FILE is missing a required field (SCOPE/BASE_COMMIT/EXPIRES_EPOCH/SESSION) — cannot evaluate."
  exit 4
fi

# 7. Session match (anti-replay): only when the caller identified itself (hook
# path). AUTONOMY_SESSION is now guaranteed non-empty by the check above, so a
# caller-supplied session always gets a real comparison — never a silent skip.
if [ -n "$CALLER_SESSION" ] && [ "$CALLER_SESSION" != "$AUTONOMY_SESSION" ]; then
  msg "run record belongs to session ${AUTONOMY_SESSION:0:8}…, caller is ${CALLER_SESSION:0:8}… — stale grant, cannot evaluate."
  exit 4
fi

# 8. BASE_COMMIT hardening (C7): reject anything that could be parsed as a git
# option instead of a revision before it ever reaches a git command line.
case "$AUTONOMY_BASE_COMMIT" in
  -*)
    msg "AUTONOMY_BASE_COMMIT ('$AUTONOMY_BASE_COMMIT') begins with '-' — rejected as unsafe, cannot evaluate."
    exit 4
    ;;
esac
case "$AUTONOMY_BASE_COMMIT" in
  *[!0-9A-Za-z._/-]*)
    msg "AUTONOMY_BASE_COMMIT ('$AUTONOMY_BASE_COMMIT') contains characters outside [0-9A-Za-z._/-] — rejected as unsafe, cannot evaluate."
    exit 4
    ;;
esac

# env override > record value > hardcoded default. Total-run caps now (C3) — no
# more per-interval/aggregate distinction, no tasks cap.
MAX_FILES="${CLAUDE_SUBTEAMS_AUTONOMY_MAX_FILES:-${AUTONOMY_MAX_FILES:-10}}"
MAX_LINES="${CLAUDE_SUBTEAMS_AUTONOMY_MAX_LINES:-${AUTONOMY_MAX_LINES:-400}}"

# Fail-closed: a cap that is present but not a plain number can never mean
# "unbounded" — a garbled record is exit 4 (cannot evaluate), same as a bad epoch.
_require_numeric() { # name value
  case "$2" in
    '') : ;;
    *[!0-9]*) msg "$1 ('$2') is not a plain number — cannot evaluate."; exit 4 ;;
  esac
}
_require_numeric MAX_FILES "$MAX_FILES"
_require_numeric MAX_LINES "$MAX_LINES"

# 9. Freshness.
case "$AUTONOMY_EXPIRES_EPOCH" in
  ''|*[!0-9]*) msg "AUTONOMY_EXPIRES_EPOCH ('$AUTONOMY_EXPIRES_EPOCH') is not a valid epoch — cannot evaluate."; exit 4 ;;
esac
NOW=$(date +%s)
if [ "$NOW" -gt "$AUTONOMY_EXPIRES_EPOCH" ]; then
  msg "grant expired at $AUTONOMY_EXPIRES_EPOCH (now $NOW) — cannot evaluate."
  exit 4
fi

if ! git -C "$PROJECT_DIR" cat-file -e "${AUTONOMY_BASE_COMMIT}^{commit}" 2>/dev/null; then
  msg "AUTONOMY_BASE_COMMIT '$AUTONOMY_BASE_COMMIT' does not resolve to a commit — cannot evaluate."
  exit 4
fi

# 10. Multi-instance single-writer check. AUTONOMY_SESSION (truncated the same way
# coord.sh derives its instance id, first 8 chars of session_id) identifies the
# session that was granted the run; any OTHER live instance in the roster means the
# single-writer invariant no longer holds — fail closed.
if [ "${CLAUDE_SUBTEAMS_MULTI_INSTANCE:-0}" = "1" ]; then
  # This is the ONE guard whose entire purpose is to fail CLOSED: unless we can
  # POSITIVELY confirm this session is the sole live instance, we stop (exit 4) —
  # we never proceed on an inability to determine. coord.sh missing/not-executable,
  # jq absent, a not-a-git-repo or lock error, or any non-zero `roster` exit all mean
  # "could not determine" and are treated identically. A successful `coord.sh roster`
  # ALWAYS prints at least a header line ("Live instances (N):" or "(no instances)"),
  # so empty output on a zero exit is itself indeterminate → also fail closed.
  SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SELF_DIR=""
  COORD="${SELF_DIR}/coord.sh"
  if [ -z "$SELF_DIR" ] || [ ! -x "$COORD" ]; then
    msg "multi-instance mode but coord.sh is missing or not executable (looked in '${SELF_DIR:-?}') — cannot confirm single-writer, cannot evaluate."
    exit 4
  fi
  if ! ROSTER=$("$COORD" roster 2>/dev/null); then
    msg "multi-instance mode but 'coord.sh roster' errored (jq missing, not a git repo, or lock failure) — cannot confirm single-writer, cannot evaluate."
    exit 4
  fi
  if [ -z "$ROSTER" ]; then
    msg "multi-instance mode but 'coord.sh roster' produced no output — cannot confirm single-writer, cannot evaluate."
    exit 4
  fi
  SELF_ID="${AUTONOMY_SESSION:0:8}"
  OTHER=$(printf '%s\n' "$ROSTER" | awk -v self="$SELF_ID" '
    /^[[:space:]]*-[[:space:]]/ { if ($2 != self) { if (out != "") out = out ","; out = out $2 } }
    END { print out }')
  if [ -n "$OTHER" ]; then
    msg "other live instance(s) on this repo ($OTHER) — single-writer required for autonomy, cannot evaluate."
    exit 4
  fi
fi

# 11. --pending=<path> (C12/B4): fold a not-yet-written path into the changed-file
# set BEFORE scope evaluation, so the hook can deny an out-of-scope write before it
# lands. G1: resolved with `_canon_path` (handles a relative path, a `../`
# round-trip, or a symlink alias — closes the "dress the pending path up so it
# doesn't textually match the record/scope" bypass) and THEN relativized against
# the canonical repo root. A resolved path that lands OUTSIDE the repo root is
# rejected outright here — exit 2, out-of-scope — rather than left to an
# incidental glob mismatch further down.
PENDING_REL=""
if [ -n "$PENDING_PATH" ]; then
  case "$PENDING_PATH" in
    /*) PENDING_ABS="$PENDING_PATH" ;;
    *) PENDING_ABS="$PROJECT_DIR/$PENDING_PATH" ;;
  esac
  PENDING_CANON=$(_canon_path "$PENDING_ABS")
  case "$PENDING_CANON" in
    "$PROJECT_DIR_CANON"/*) PENDING_REL="${PENDING_CANON#"$PROJECT_DIR_CANON"/}" ;;
    "$PROJECT_DIR_CANON") PENDING_REL="." ;;
    *)
      msg "pending path '$PENDING_PATH' resolves to '$PENDING_CANON', which is outside the repository root ($PROJECT_DIR_CANON) — out of scope."
      exit 2
      ;;
  esac
fi

# 12. Scope evaluation: union of diff-vs-base + untracked, both sides of a rename,
# plus the pre-hoc pending path if given. core.quotePath=false (C8) so unicode
# paths compare equal to scope globs and the record-file exemption; --end-of-options
# (C7) stops a hostile-looking BASE_COMMIT from being parsed as a git option; the
# trailing `--` disambiguates revision vs pathspec (G6 hygiene, no paths follow it
# here — an explicit terminator regardless).
# AC3: each git invocation's exit status is checked explicitly. Under `set -uo
# pipefail` (no -e) a FAILED git call otherwise yields an empty string, silently
# read as "0 changed files / 0 lines" — scope and cap checks would then PASS on a
# git error. An EMPTY-but-successful result (genuinely no changes) still proceeds;
# only a NON-ZERO git exit fails closed. pipefail makes the awk-piped case below
# surface git's failure too (rightmost non-zero status wins).
if ! DIFF_NAMES=$(git -C "$PROJECT_DIR" -c core.quotePath=false diff --name-only --end-of-options "$AUTONOMY_BASE_COMMIT" -- 2>/dev/null); then
  msg "git diff --name-only against base failed — cannot evaluate (a git error is not an empty changeset)."
  exit 4
fi
if ! UNTRACKED_FILES=$(git -C "$PROJECT_DIR" -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null); then
  msg "git ls-files --others failed — cannot evaluate (a git error is not an empty changeset)."
  exit 4
fi
if ! RENAME_NAMES=$(git -C "$PROJECT_DIR" -c core.quotePath=false diff --name-status --end-of-options "$AUTONOMY_BASE_COMMIT" -- 2>/dev/null \
  | awk -F'\t' '$1 ~ /^R/ { print $2; print $3 }'); then
  msg "git diff --name-status against base failed — cannot evaluate (a git error is not an empty changeset)."
  exit 4
fi

CHANGED_FILES=$(
  {
    printf '%s\n' "$DIFF_NAMES"
    printf '%s\n' "$UNTRACKED_FILES"
    printf '%s\n' "$RENAME_NAMES"
    [ -n "$PENDING_REL" ] && printf '%s\n' "$PENDING_REL"
  } | awk 'NF' | awk '!seen[$0]++'
)

IFS=',' read -r -a SCOPE_GLOBS <<< "$AUTONOMY_SCOPE"
# The active record file is auto-exempt: --checkpoint writes to it every run, so
# it always differs from base. Exempting it is safe under the stated model (an
# agent editing the plan file is the accepted "script-authored assumption" caveat).
# It is also excluded from FILES_COUNT (C4) so the cap reflects real work files.
# G1: relativized through the SAME canonicalization pipeline as PENDING_REL above,
# so a canonicalized pending path that genuinely resolves to the record cannot
# fail to match it (nor can an unrelated path falsely collide with it) due to the
# two sides being relativized differently.
RECORD_CANON=$(_canon_path "$RECORD_FILE")
case "$RECORD_CANON" in
  "$PROJECT_DIR_CANON"/*) RECORD_REL="${RECORD_CANON#"$PROJECT_DIR_CANON"/}" ;;
  *) RECORD_REL="${RECORD_FILE#"$PROJECT_DIR"/}" ;;
esac
VIOLATIONS=""
NONEXEMPT_COUNT=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ "$path" = "$RECORD_REL" ] && continue
  NONEXEMPT_COUNT=$((NONEXEMPT_COUNT + 1))
  MATCHED=0
  for glob in "${SCOPE_GLOBS[@]}"; do
    # Trim runs of leading/trailing whitespace (C10), not just one space.
    while [ "${glob# }" != "$glob" ]; do glob="${glob# }"; done
    while [ "${glob% }" != "$glob" ]; do glob="${glob% }"; done
    [ -n "$glob" ] || continue
    case "$path" in
      $glob) MATCHED=1; break ;;
    esac
  done
  if [ "$MATCHED" -eq 0 ]; then
    VIOLATIONS="${VIOLATIONS}${VIOLATIONS:+,}${path}"
  fi
done <<< "$CHANGED_FILES"

if [ -n "$VIOLATIONS" ]; then
  msg "out-of-scope path(s) not covered by AUTONOMY_SCOPE ($AUTONOMY_SCOPE): $VIOLATIONS"
  exit 2
fi

# 13. Caps: TOTAL-RUN, cumulative from AUTONOMY_BASE_COMMIT — recomputed fresh from
# git on every call (C3: no per-interval/aggregate split, no budget/tasks fields).
FILES_COUNT="$NONEXEMPT_COUNT"
# G5: LINES is computed over the CHANGED_FILES set MINUS the record file — NOT a
# whole-repo --shortstat. A whole-repo shortstat would silently count the record's
# own diff (an appended AUTONOMY_CHECKPOINT line, an AC status flip) against the
# agent's line budget even though that same file is already exempt from scope and
# FILES_COUNT — a run whose only change is the record's own bookkeeping must report
# lines=0, not false-block on it.
TRACKED_NONRECORD=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ "$p" = "$RECORD_REL" ] && continue
  TRACKED_NONRECORD+=("$p")
done <<< "$DIFF_NAMES"
TRACKED_LINES=0
if [ "${#TRACKED_NONRECORD[@]}" -gt 0 ]; then
  # AC3: a failed numstat must not silently read as 0 lines (which would pass the cap).
  if ! NUMSTAT=$(git -C "$PROJECT_DIR" -c core.quotePath=false diff --numstat --end-of-options "$AUTONOMY_BASE_COMMIT" -- "${TRACKED_NONRECORD[@]}" 2>/dev/null); then
    msg "git diff --numstat against base failed — cannot evaluate (a git error is not zero lines)."
    exit 4
  fi
  TRACKED_LINES=$(printf '%s\n' "$NUMSTAT" | awk -F'\t' '
    NF>=2 { if ($1 ~ /^[0-9]+$/) a+=$1; if ($2 ~ /^[0-9]+$/) d+=$2 }
    END { print a+d+0 }')
fi
# Untracked new files have no diff at all (C5) — summed separately via wc -l, same
# record exclusion applied.
UNTRACKED_LINES=0
if [ -n "$UNTRACKED_FILES" ]; then
  UNTRACKED_LINES=$(printf '%s\n' "$UNTRACKED_FILES" | awk 'NF' | awk -v rec="$RECORD_REL" '$0 != rec' | while IFS= read -r uf; do
    [ -f "$PROJECT_DIR/$uf" ] && wc -l < "$PROJECT_DIR/$uf"
  done | awk '{s+=$1} END{print s+0}')
fi
LINES_COUNT=$((TRACKED_LINES + UNTRACKED_LINES))

if [ "$FILES_COUNT" -gt "$MAX_FILES" ]; then
  msg "files changed ($FILES_COUNT) exceeds AUTONOMY_MAX_FILES ($MAX_FILES) — total-run cap, cumulative from base."
  exit 2
fi
if [ "$LINES_COUNT" -gt "$MAX_LINES" ]; then
  msg "lines changed ($LINES_COUNT) exceeds AUTONOMY_MAX_LINES ($MAX_LINES) — total-run cap, cumulative from base."
  exit 2
fi

# 14. On success: append a script-authored, audit-only checkpoint line if asked.
# Read-only otherwise. Nothing consumes this line for enforcement.
if [ "$CHECKPOINT" -eq 1 ]; then
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  LINE="AUTONOMY_CHECKPOINT: ${TS} files=${FILES_COUNT} lines=${LINES_COUNT} exit=0"
  TMP=$(mktemp "${RECORD_FILE}.XXXXXX" 2>/dev/null) || { msg "checkpoint append failed (mktemp) — cannot evaluate."; exit 4; }
  if ! awk -v line="$LINE" '
        /<!-- autonomy-run:end -->/ && !done { print line; done=1 }
        { print }
      ' "$RECORD_FILE" > "$TMP" || ! mv "$TMP" "$RECORD_FILE"; then
    rm -f "$TMP" 2>/dev/null
    msg "checkpoint append failed (write) — cannot evaluate."
    exit 4
  fi
  msg "OK (checkpoint recorded, audit only) — files=$FILES_COUNT/$MAX_FILES lines=$LINES_COUNT/$MAX_LINES (total-run, cumulative from base)."
  exit 0
fi

msg "OK — files=$FILES_COUNT/$MAX_FILES lines=$LINES_COUNT/$MAX_LINES (total-run cap, cumulative from base)."
exit 0
