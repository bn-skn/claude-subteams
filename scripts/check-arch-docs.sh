#!/bin/bash
# check-arch-docs.sh — verify that ARCHITECTURE.md and CONVENTIONS.md are
# populated (no stub markers remain) and that their ADR references resolve.
#
# Usage: bash scripts/check-arch-docs.sh [project-dir]
#   project-dir  defaults to current directory (.)
#
# Exit 0 — both files exist, contain no stub markers, and every ADR link in
#          ARCHITECTURE.md resolves to an existing file.
# Exit 1 — a file is missing, a stub marker remains, or an ADR link dangles.
#
# Shared Contract — stub markers that mean a template was never filled:
#   > STATUS: TEMPLATE — not yet populated   (the sentinel — primary signal)
#   <PLACEHOLDER                              (any unfilled angle-bracket placeholder)
#   ADR-NNN                                   (unfilled Decision Records placeholder)
#   NNN-title                                 (unfilled ADR link target)
#
# Note on markers: bare `<!--` and `ComponentName` are deliberately NOT markers —
# legitimate populated docs may carry HTML comments or a component literally named
# with that substring; matching them produced false positives on honest docs.
# Emptiness is caught by the sentinel + <PLACEHOLDER; fabrication (a real-looking
# architecture pointing at ADRs that do not exist) is caught by the ADR link check.

set -uo pipefail

PROJECT_DIR="${1:-.}"
DOCS_DIR="${PROJECT_DIR}/docs"

ARCH_FILE="${DOCS_DIR}/ARCHITECTURE.md"
CONV_FILE="${DOCS_DIR}/CONVENTIONS.md"

# Stub markers from the Shared Contract (fixed-string, grep -F).
MARKERS=(
  '> STATUS: TEMPLATE — not yet populated'
  '<PLACEHOLDER'
  'ADR-NNN'
  'NNN-title'
)

FAILED=0

# check_file FILE — flag a missing file or any stub marker. Never exits early.
check_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "  MISSING: $file"
    FAILED=1
    return
  fi

  local marker rc
  for marker in "${MARKERS[@]}"; do
    # grep -qF: quiet fixed-string. rc 0 = found, 1 = not found, 2 = error.
    # Captured explicitly so a 'not found' (rc 1) never aborts the loop.
    rc=0
    grep -qF "$marker" "$file" || rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "  STUB MARKER in $file: $marker"
      FAILED=1
    fi
  done
}

# check_adr_links FILE — every markdown link to adr/*.md must resolve to a real
# file under docs/adr/. A dangling link is the fabrication signal: a plausible
# architecture that cites Decision Records which were never written.
check_adr_links() {
  local file="$1"
  [ -f "$file" ] || return

  local link target
  # Extract adr/<...>.md link targets (markdown link bodies). rc 1 = none found.
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    target="${DOCS_DIR}/${link}"
    if [ ! -f "$target" ]; then
      echo "  DANGLING ADR LINK in $file: $link → $target not found"
      FAILED=1
    fi
  done < <(grep -oE 'adr/[A-Za-z0-9._/-]+\.md' "$file" 2>/dev/null || true)
}

echo "[check-arch-docs] Checking: $ARCH_FILE"
check_file "$ARCH_FILE"
check_adr_links "$ARCH_FILE"

echo "[check-arch-docs] Checking: $CONV_FILE"
check_file "$CONV_FILE"

if [ "$FAILED" -eq 1 ]; then
  echo ""
  echo "[check-arch-docs] FAIL — stub markers, missing files, or dangling ADR links detected."
  echo "  Populate the docs via the brainstorming capture flow before proceeding."
  exit 1
fi

echo ""
echo "[check-arch-docs] PASS — both docs are populated and ADR links resolve."
exit 0
