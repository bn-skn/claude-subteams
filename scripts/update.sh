#!/bin/bash
# Update claude-subteams via the official Claude Code marketplace CLI.
#
# Equivalent Claude Code command:
#   /plugin marketplace update articortex

set -euo pipefail

MARKETPLACE_NAME="articortex"
PLUGIN_NAME="claude-subteams"

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

# NOTE: verify exact subcommand against 'claude plugin marketplace --help'
# if this fails with "unknown command", the CLI version may differ.
claude plugin marketplace update "$MARKETPLACE_NAME"

echo ""
echo "[claude-subteams] Update complete."
echo "  Restart Claude Code to apply changes (/reload-plugins or new session)."
