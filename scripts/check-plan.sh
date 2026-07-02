#!/bin/bash
# check-plan.sh — validate the living plan-of-record file(s) under
# docs/plans/active/IMPL-PLAN-*.md (see the living-plan skill).
#
# Usage: bash scripts/check-plan.sh [project-dir]
#   project-dir  defaults to current directory (.)
#
# Exit 0 — no plan-of-record present (legitimate), OR every IMPL-PLAN is valid:
#          sentinel removed, a Rollup table present, and every checklist item
#          carries a recognized status token.
# Exit 1 — a plan-of-record exists but is malformed (printed).
#
# A plan-of-record is OPTIONAL — its absence is never a failure. This script only
# guards the integrity of one that exists. Mechanical evidence, not self-attestation.

set -uo pipefail

PROJECT_DIR="${1:-.}"
ACTIVE_DIR="${PROJECT_DIR}/docs/plans/active"

SENTINEL='> STATUS: TEMPLATE — not yet populated'
# A well-formed checklist item carries its status as a TRAILING marker after a
# separator — `— DONE`, `— TODO`, `-- WIP`, ` - BLOCKED` — OR the unresolved marker
# `TBD` (authored as `**TBD — unresolved**`). Anchoring to a separator avoids matching
# a status word that merely appears in the criterion's prose (e.g. "never BLOCKED by
# overload"); the bare `TBD` literal is safe (it does not occur incidentally).
STATUS_RE='(—|--|[[:space:]]-[[:space:]])[[:space:]]*(DONE|WIP|TODO|BLOCKED)|TBD'

FAILED=0

# Gather IMPL-PLAN files without relying on nullglob.
PLANS=()
if [ -d "$ACTIVE_DIR" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && PLANS+=("$f")
  done < <(find "$ACTIVE_DIR" -maxdepth 1 -type f -name 'IMPL-PLAN-*.md' 2>/dev/null || true)
fi

if [ "${#PLANS[@]}" -eq 0 ]; then
  echo "[check-plan] No docs/plans/active/IMPL-PLAN-*.md — nothing to validate (OK)."
  exit 0
fi

check_plan() {
  local file="$1"
  echo "[check-plan] Checking: $file"

  # 0. Size guard (D2/M3): never parse a plan file larger than 1MB. An
  #    unvalidatable plan is a FAILURE, not a pass — the header contract is
  #    "Exit 0 = every IMPL-PLAN is valid", and a file we refused to parse was
  #    never shown valid. Set FAILED=1 so exit is non-zero even when this is the
  #    only plan (AC8); keep the SKIPPED diagnostic.
  local fsize
  fsize=$(wc -c < "$file" 2>/dev/null || echo 0)
  if [ "$fsize" -gt 1048576 ]; then
    echo "  SKIPPED: file exceeds 1MB ($fsize bytes) — not parsed (DoS guard); treated as FAIL (unvalidatable)."
    FAILED=1
    return
  fi

  # 1. Sentinel must be gone once populated.
  if grep -qF "$SENTINEL" "$file"; then
    echo "  STUB: template sentinel still present (remove it once populated)."
    FAILED=1
  fi

  # 2. A Rollup table must exist.
  if ! grep -qE '^##[[:space:]]+Rollup' "$file"; then
    echo "  MISSING: a '## Rollup' section."
    FAILED=1
  fi

  # 3+4. Checklist status markers and REVISED-line shape, in a SINGLE awk pass over
  #    the file (D2/M3: the previous per-line grep|awk pipeline forked up to 4
  #    processes per checklist/REVISED line — a fork-storm on a large plan).
  #    Checklist lines look like:  - [ ] ...   or   - [x] ...
  #    REVISED lines require AT LEAST 3 ' — '-separated parts (D1, code-reviewer +
  #    Codex): `REVISED: <what> — <why> — <ack>`, allowing the ack quote itself to
  #    contain ' — ' without being misread as malformed.
  local awk_out
  awk_out=$(awk '
    {
      line = $0
      if (line ~ /^[[:space:]]*-[[:space:]]\[[ xX]\]/) {
        if (line !~ /(—|--|[[:space:]]-[[:space:]])[[:space:]]*(DONE|WIP|TODO|BLOCKED)|TBD/) {
          trimmed = line
          sub(/^[[:space:]]+/, "", trimmed)
          print "STATUSBAD\t" NR "\t" trimmed
          statusbad++
        }
      }
      if (line ~ /^[[:space:]]*REVISED:/) {
        revised++
        parts = split(line, arr, " — ")
        if (parts < 3) {
          trimmed = line
          sub(/^[[:space:]]+/, "", trimmed)
          print "REVISEDBAD\t" NR "\t" parts "\t" trimmed
          revisedbad++
        }
      }
    }
    END { print "SUMMARY\t" (statusbad + 0) "\t" (revised + 0) "\t" (revisedbad + 0) }
  ' "$file")

  local bad=0 rbad=0 rcount=0
  while IFS=$'\t' read -r kind a b c; do
    case "$kind" in
      STATUSBAD)
        echo "  NO STATUS MARKER (line $a): $b"
        bad=1
        FAILED=1
        ;;
      REVISEDBAD)
        echo "  MALFORMED REVISED (line $a): expected 'REVISED: <what> — <why> — <ack>' (at least 3 parts, found $b): $c"
        rbad=1
        FAILED=1
        ;;
      SUMMARY)
        rcount="$b"
        ;;
    esac
  done <<< "$awk_out"

  [ "$bad" -eq 0 ] && echo "  checklist items: all carry a status token."
  if [ "$rcount" -gt 0 ] && [ "$rbad" -eq 0 ]; then
    echo "  REVISED lines: all $rcount well-formed."
  fi
}

for f in "${PLANS[@]}"; do
  check_plan "$f"
done

echo ""
if [ "$FAILED" -eq 1 ]; then
  echo "[check-plan] FAIL — a plan-of-record is malformed (see above). Fix per the living-plan skill."
  exit 1
fi

echo "[check-plan] PASS — ${#PLANS[@]} plan-of-record file(s) valid."
exit 0
