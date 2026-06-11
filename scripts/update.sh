#!/bin/bash
# Update claude-subteams via the official Claude Code CLI.
#
# Equivalent Claude Code commands (run both, then restart):
#   /plugin marketplace update articortex
#   /plugin update claude-subteams@articortex

set -euo pipefail

MARKETPLACE_NAME="articortex"
PLUGIN_NAME="claude-subteams"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

echo "[claude-subteams] Updating..."

if ! command -v claude &>/dev/null; then
  echo "[claude-subteams] ERROR: 'claude' CLI not found on PATH." >&2
  exit 1
fi

# Guard: confirm the marketplace is registered before trying to update.
if ! claude plugin marketplace list 2>/dev/null | grep -qF "$MARKETPLACE_NAME"; then
  echo "[claude-subteams] ERROR: marketplace '$MARKETPLACE_NAME' not found." >&2
  echo "  Run install.sh first to register the marketplace and install the plugin." >&2
  exit 1
fi

# Step 1 — refresh the marketplace catalog (pull latest main from the repo).
# NOTE: verify exact subcommand against 'claude plugin marketplace --help'
# if this fails with "unknown command", the CLI version may differ.
claude plugin marketplace update "$MARKETPLACE_NAME"

# Step 2 — upgrade the INSTALLED plugin to that version. Without this, the catalog
# refreshes but the version-pinned installed plugin stays on the old version.
# 'plugin update' is a no-op (or harmless) if already current.
claude plugin update "$PLUGIN_KEY"

echo ""
echo "[claude-subteams] Update complete."
echo "  Restart Claude Code to apply changes (/reload-plugins or new session)."
