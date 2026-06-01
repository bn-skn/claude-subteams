#!/bin/bash
# Uninstall claude-subteams via the official Claude Code plugin CLI.
#
# Equivalent Claude Code commands:
#   /plugin uninstall claude-subteams@articortex
#   /plugin marketplace remove articortex   (optional — removes marketplace entry)

set -euo pipefail

# --- Safety checks ------------------------------------------------------------

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "[claude-subteams] ERROR: \$HOME is unset or root. Aborting." >&2
  exit 1
fi

MARKETPLACE_NAME="articortex"
PLUGIN_NAME="claude-subteams"

echo "[claude-subteams] Uninstalling..."

if ! command -v claude &>/dev/null; then
  echo "[claude-subteams] ERROR: 'claude' CLI not found on PATH." >&2
  exit 1
fi

# --- Uninstall plugin (idempotent) -------------------------------------------

# NOTE: verify exact subcommand against 'claude plugin --help'
# if this fails with "unknown command", the CLI version may differ.
if claude plugin uninstall "${PLUGIN_NAME}@${MARKETPLACE_NAME}" 2>/dev/null; then
  echo "[claude-subteams] Plugin removed."
else
  echo "[claude-subteams] Plugin was not installed or already removed — continuing."
fi

# --- Optionally remove marketplace entry -------------------------------------

if [ "${1:-}" = "--remove-marketplace" ]; then
  echo "[claude-subteams] Removing marketplace '$MARKETPLACE_NAME'..."
  # Safe to remove: the articortex marketplace currently has ONE plugin (claude-subteams).
  # Revisit this if a second plugin is ever added to the marketplace before removing.
  # NOTE: verify exact subcommand against 'claude plugin marketplace --help'
  claude plugin marketplace remove "$MARKETPLACE_NAME" 2>/dev/null || \
    echo "[claude-subteams] Marketplace entry not found or already removed."
fi

# --- Done ---------------------------------------------------------------------

echo ""
echo "[claude-subteams] Uninstall complete."
echo "  Note: Project-level files (BACKLOG.md, CONVENTIONS.md, etc.) were NOT removed."
echo "  Also remove the snippet from your CLAUDE.md if you added it."
echo "  Pass --remove-marketplace to also deregister the articortex marketplace."
echo "  Restart Claude Code for changes to take effect."
