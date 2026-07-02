#!/bin/bash
# autonomy-check.sh — deterministic scope/cap gate for Tier 2 "bounded autonomous
# execution" (see the Autonomy Mode section of the living-plan skill). Evaluates the
# active run record embedded in docs/plans/active/IMPL-PLAN-*.md (between the
# `<!-- autonomy-run:begin/end -->` markers, schema pinned in IMPL-PLAN P1) and
# decides whether the current working tree is still inside its granted scope/caps.
#
# Usage: bash scripts/autonomy-check.sh [project-dir] [--checkpoint] [--session=<id>]
#   project-dir   defaults to current directory (.)
#   --checkpoint  on exit 0 ONLY: append a script-authored AUTONOMY_CHECKPOINT line
#                 to the record (evidence for the aggregate budget check). Without
#                 this flag the script is entirely read-only.
#   --session=ID  caller session id (hooks pass it from stdin JSON). When provided,
#                 it must match the record's AUTONOMY_SESSION — a mismatch means a
#                 different session is reusing an old grant (exit 4). CLI calls
#                 without it skip the check (evidence mode).
#
# Deps: git, grep, awk ONLY (no jq — must run in every plugin-consumer repo without
# imposing a new dependency).
#
# Scope glob semantics: bash case-patterns — `*` crosses `/`, so `src/*` matches the
# WHOLE subtree (recursive), not just direct children. Write scopes accordingly.
# The active record file itself is auto-exempt from scope (script-managed).
# Honesty note: prior AUTONOMY_CHECKPOINT lines feed the aggregate budget; an agent
# DELETING them to reset the budget is not structurally prevented — that residual
# trust is the documented "script-authored assumption" (per-interval caps are always
# recomputed from git and cannot be spoofed).
#
# Exit 0 — proceed: env set, exactly one fresh record found, in scope, under caps.
# Exit 1 — usage error (bad arguments).
# Exit 2 — VIOLATION (operator-decision-required): an out-of-scope path, or a
#          per-interval/aggregate cap exceeded. The offending path(s)/numbers are
#          printed.
# Exit 3 — CLAUDE_SUBTEAMS_AUTONOMY is unset: autonomy mode is not active. This is
#          the normal manual-mode result, not an error.
# Exit 4 — CANNOT EVALUATE (fail-closed, distinct from a violation): zero or more
#          than one active record, missing/unparseable fields, expired grant, base
#          commit unresolvable, not a git repo, or (multi-instance mode) another
#          live instance is present — single-writer required for autonomy.
#
# ALL non-zero exit codes mean STOP — callers (notably hooks/autonomy-gate) must
# treat 1/2/3/4 identically as "do not proceed automatically".

set -uo pipefail

msg() { echo "[autonomy-check] $*"; }
usage_err() {
  echo "[autonomy-check] Usage: bash scripts/autonomy-check.sh [project-dir] [--checkpoint]" >&2
  exit 1
}

PROJECT_DIR="."
CHECKPOINT=0
CALLER_SESSION=""
POSITIONAL_SEEN=0
for arg in "$@"; do
  case "$arg" in
    --checkpoint) CHECKPOINT=1 ;;
    --session=*) CALLER_SESSION="${arg#--session=}" ;;
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

# 2. Locate the run record: exactly one active IMPL-PLAN carrying a record block.
ACTIVE_DIR="${PROJECT_DIR}/docs/plans/active"
CANDIDATES=()
if [ -d "$ACTIVE_DIR" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
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

# 3. Extract the record block (between the markers) and parse its fields.
RECORD=$(awk '/<!-- autonomy-run:begin -->/{f=1;next} /<!-- autonomy-run:end -->/{f=0} f' "$RECORD_FILE")
# Normalize: the schema allows several keys on one line separated by 2+ spaces
# (e.g. "AUTONOMY_MAX_FILES: 10   AUTONOMY_MAX_LINES: 400"). Split them so the
# prefix-anchored parser below sees one key per line, and trailing "(comment)"
# annotations after 2+ spaces are dropped.
RECORD=$(printf '%s\n' "$RECORD" | awk '{
  line=$0
  while (match(line, /[[:space:]][[:space:]]+AUTONOMY_[A-Z_]+:/)) {
    print substr(line, 1, RSTART-1)
    line=substr(line, RSTART)
    sub(/^[[:space:]]+/, "", line)
  }
  sub(/[[:space:]][[:space:]]+\(.*\)[[:space:]]*$/, "", line)
  print line
}')
if [ -z "$RECORD" ]; then
  msg "run record markers present in $RECORD_FILE but the block is empty — cannot evaluate."
  exit 4
fi

# First-match, prefix-anchored on "KEY: " (rejoins the value if it itself contains ": ").
_field() {
  printf '%s\n' "$RECORD" | awk -F': ' -v k="$1" '
    $1==k { out=$2; for(i=3;i<=NF;i++) out=out ": " $i; print out; exit }'
}
# All matches, in order (used for the repeatable AUTONOMY_CHECKPOINT lines).
_field_all() {
  printf '%s\n' "$RECORD" | awk -F': ' -v k="$1" '
    $1==k { out=$2; for(i=3;i<=NF;i++) out=out ": " $i; print out }'
}

AUTONOMY_SCOPE=$(_field AUTONOMY_SCOPE)
AUTONOMY_BASE_COMMIT=$(_field AUTONOMY_BASE_COMMIT)
AUTONOMY_SESSION=$(_field AUTONOMY_SESSION)
# Session match (anti-replay): only when the caller identified itself (hook path).
if [ -n "$CALLER_SESSION" ] && [ -n "$AUTONOMY_SESSION" ] && [ "$CALLER_SESSION" != "$AUTONOMY_SESSION" ]; then
  msg "run record belongs to session ${AUTONOMY_SESSION:0:8}…, caller is ${CALLER_SESSION:0:8}… — stale grant, cannot evaluate."
  exit 4
fi
AUTONOMY_EXPIRES_EPOCH=$(_field AUTONOMY_EXPIRES_EPOCH)
AUTONOMY_MAX_FILES=$(_field AUTONOMY_MAX_FILES)
AUTONOMY_MAX_LINES=$(_field AUTONOMY_MAX_LINES)
AUTONOMY_BUDGET_FILES=$(_field AUTONOMY_BUDGET_FILES)
AUTONOMY_BUDGET_TASKS=$(_field AUTONOMY_BUDGET_TASKS)

if [ -z "$AUTONOMY_SCOPE" ] || [ -z "$AUTONOMY_BASE_COMMIT" ] || [ -z "$AUTONOMY_EXPIRES_EPOCH" ]; then
  msg "run record in $RECORD_FILE is missing a required field (SCOPE/BASE_COMMIT/EXPIRES_EPOCH) — cannot evaluate."
  exit 4
fi

# env override > record value > hardcoded default.
MAX_FILES="${CLAUDE_SUBTEAMS_AUTONOMY_MAX_FILES:-${AUTONOMY_MAX_FILES:-10}}"
MAX_LINES="${CLAUDE_SUBTEAMS_AUTONOMY_MAX_LINES:-${AUTONOMY_MAX_LINES:-400}}"

# Fail-closed: a cap/budget that is present but not a plain number can never mean
# "unbounded" — a garbled record is exit 4 (cannot evaluate), same as a bad epoch.
_require_numeric() { # name value — empty is allowed (defaults/skips handle it)
  case "$2" in
    '') : ;;
    *[!0-9]*) msg "$1 ('$2') is not a plain number — cannot evaluate."; exit 4 ;;
  esac
}
_require_numeric MAX_FILES "$MAX_FILES"
_require_numeric MAX_LINES "$MAX_LINES"
_require_numeric AUTONOMY_BUDGET_FILES "$AUTONOMY_BUDGET_FILES"
_require_numeric AUTONOMY_BUDGET_TASKS "$AUTONOMY_BUDGET_TASKS"

# 4. Freshness.
case "$AUTONOMY_EXPIRES_EPOCH" in
  ''|*[!0-9]*) msg "AUTONOMY_EXPIRES_EPOCH ('$AUTONOMY_EXPIRES_EPOCH') is not a valid epoch — cannot evaluate."; exit 4 ;;
esac
NOW=$(date +%s)
if [ "$NOW" -gt "$AUTONOMY_EXPIRES_EPOCH" ]; then
  msg "grant expired at $AUTONOMY_EXPIRES_EPOCH (now $NOW) — cannot evaluate."
  exit 4
fi

if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  msg "$PROJECT_DIR is not a git repository — cannot evaluate."
  exit 4
fi
if ! git -C "$PROJECT_DIR" cat-file -e "${AUTONOMY_BASE_COMMIT}^{commit}" 2>/dev/null; then
  msg "AUTONOMY_BASE_COMMIT '$AUTONOMY_BASE_COMMIT' does not resolve to a commit — cannot evaluate."
  exit 4
fi

# 5. Multi-instance single-writer check. AUTONOMY_SESSION (truncated the same way
# coord.sh derives its instance id, first 8 chars of session_id) identifies the
# session that was granted the run; any OTHER live instance in the roster means the
# single-writer invariant no longer holds — fail closed.
if [ "${CLAUDE_SUBTEAMS_MULTI_INSTANCE:-0}" = "1" ]; then
  SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SELF_DIR=""
  COORD="${SELF_DIR}/coord.sh"
  if [ -n "$SELF_DIR" ] && [ -x "$COORD" ]; then
    ROSTER=$("$COORD" roster 2>/dev/null)
    SELF_ID="${AUTONOMY_SESSION:0:8}"
    OTHER=$(printf '%s\n' "$ROSTER" | awk -v self="$SELF_ID" '
      /^[[:space:]]*-[[:space:]]/ { if ($2 != self) { if (out != "") out = out ","; out = out $2 } }
      END { print out }')
    if [ -n "$OTHER" ]; then
      msg "other live instance(s) on this repo ($OTHER) — single-writer required for autonomy, cannot evaluate."
      exit 4
    fi
  fi
fi

# 6. Scope evaluation: union of diff-vs-base + untracked, both sides of a rename.
CHANGED_FILES=$(
  {
    git -C "$PROJECT_DIR" diff --name-only "$AUTONOMY_BASE_COMMIT" 2>/dev/null
    git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null
    git -C "$PROJECT_DIR" diff --name-status "$AUTONOMY_BASE_COMMIT" 2>/dev/null \
      | awk -F'\t' '$1 ~ /^R/ { print $2; print $3 }'
  } | awk 'NF' | awk '!seen[$0]++'
)

IFS=',' read -r -a SCOPE_GLOBS <<< "$AUTONOMY_SCOPE"
# The active record file is auto-exempt: --checkpoint writes to it every interval,
# so it always differs from base. Exempting it is safe under the stated model (an
# agent editing the plan file is the accepted "script-authored assumption" caveat).
RECORD_REL="${RECORD_FILE#"$PROJECT_DIR"/}"
VIOLATIONS=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ "$path" = "$RECORD_REL" ] && continue
  MATCHED=0
  for glob in "${SCOPE_GLOBS[@]}"; do
    glob="${glob# }"; glob="${glob% }"
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

# 7. Caps: per-interval (files/lines changed since base) + aggregate budget (sum of
# prior script-authored AUTONOMY_CHECKPOINT lines vs BUDGET_FILES/BUDGET_TASKS).
FILES_COUNT=$(printf '%s\n' "$CHANGED_FILES" | awk 'NF' | wc -l | awk '{print $1}')
SHORTSTAT=$(git -C "$PROJECT_DIR" diff --shortstat "$AUTONOMY_BASE_COMMIT" 2>/dev/null)
INSERTIONS=$(printf '%s' "$SHORTSTAT" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^insertion/) print $(i-1) }')
DELETIONS=$(printf '%s' "$SHORTSTAT" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^deletion/) print $(i-1) }')
INSERTIONS="${INSERTIONS:-0}"
DELETIONS="${DELETIONS:-0}"
LINES_COUNT=$((INSERTIONS + DELETIONS))

if [ "$FILES_COUNT" -gt "$MAX_FILES" ]; then
  msg "files changed ($FILES_COUNT) exceeds AUTONOMY_MAX_FILES ($MAX_FILES)."
  exit 2
fi
if [ "$LINES_COUNT" -gt "$MAX_LINES" ]; then
  msg "lines changed ($LINES_COUNT) exceeds AUTONOMY_MAX_LINES ($MAX_LINES)."
  exit 2
fi

CP_LINES=$(_field_all AUTONOMY_CHECKPOINT)
AGG_FILES=0
AGG_TASKS=0
if [ -n "$CP_LINES" ]; then
  AGG_FILES=$(printf '%s\n' "$CP_LINES" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^files=/) { split($i,a,"="); s+=a[2] } } END{print s+0}')
  AGG_TASKS=$(printf '%s\n' "$CP_LINES" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^tasks=/) { split($i,a,"="); s+=a[2] } } END{print s+0}')
fi
CUR_TASKS="${CLAUDE_SUBTEAMS_AUTONOMY_TASK:-1}"
case "$CUR_TASKS" in ''|*[!0-9]*) CUR_TASKS=1 ;; esac

if [ -n "$AUTONOMY_BUDGET_FILES" ]; then
  TOTAL_FILES=$((AGG_FILES + FILES_COUNT))
  if [ "$TOTAL_FILES" -gt "$AUTONOMY_BUDGET_FILES" ]; then
    msg "aggregate files ($TOTAL_FILES = $AGG_FILES prior + $FILES_COUNT current) exceeds AUTONOMY_BUDGET_FILES ($AUTONOMY_BUDGET_FILES)."
    exit 2
  fi
fi
if [ -n "$AUTONOMY_BUDGET_TASKS" ]; then
  TOTAL_TASKS=$((AGG_TASKS + CUR_TASKS))
  if [ "$TOTAL_TASKS" -gt "$AUTONOMY_BUDGET_TASKS" ]; then
    msg "aggregate tasks ($TOTAL_TASKS = $AGG_TASKS prior + $CUR_TASKS current) exceeds AUTONOMY_BUDGET_TASKS ($AUTONOMY_BUDGET_TASKS)."
    exit 2
  fi
fi

# 8. On success: append a script-authored checkpoint line if asked. Read-only otherwise.
if [ "$CHECKPOINT" -eq 1 ]; then
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  LINE="AUTONOMY_CHECKPOINT: ${TS} files=${FILES_COUNT} lines=${LINES_COUNT} tasks=${CUR_TASKS} exit=0"
  TMP=$(mktemp "${RECORD_FILE}.XXXXXX" 2>/dev/null) || { msg "checkpoint append failed (mktemp) — cannot evaluate."; exit 4; }
  if ! awk -v line="$LINE" '
        /<!-- autonomy-run:end -->/ && !done { print line; done=1 }
        { print }
      ' "$RECORD_FILE" > "$TMP" || ! mv "$TMP" "$RECORD_FILE"; then
    rm -f "$TMP" 2>/dev/null
    msg "checkpoint append failed (write) — cannot evaluate."
    exit 4
  fi
  msg "OK (checkpoint recorded) — files=$FILES_COUNT/$MAX_FILES lines=$LINES_COUNT/$MAX_LINES tasks=$CUR_TASKS."
  exit 0
fi

msg "OK — files=$FILES_COUNT/$MAX_FILES lines=$LINES_COUNT/$MAX_LINES."
exit 0
