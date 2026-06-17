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
# Recognized status tokens for a checklist item.
TOKEN_RE='(DONE|WIP|TODO|BLOCKED)'

FAILED=0
FOUND=0

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
  FOUND=1
  echo "[check-plan] Checking: $file"

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

  # 3. Every checklist item must carry a recognized status token.
  #    Checklist lines look like:  - [ ] ...   or   - [x] ...
  local line lineno=0 bad=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in
      *"- ["*"]"*)
        # Only treat genuine task checkboxes (- [ ] / - [x] / - [X]) as items.
        if printf '%s' "$line" | grep -qE '^[[:space:]]*-[[:space:]]\[[ xX]\]'; then
          if ! printf '%s' "$line" | grep -qE "$TOKEN_RE"; then
            echo "  NO STATUS TOKEN (line $lineno): ${line# }"
            bad=1
            FAILED=1
          fi
        fi
        ;;
    esac
  done < "$file"
  [ "$bad" -eq 0 ] && echo "  checklist items: all carry a status token."
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
