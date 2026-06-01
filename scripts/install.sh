#!/bin/bash
# Install claude-subteams via the official Claude Code plugin marketplace.
#
# Primary path (inside Claude Code):
#   /plugin marketplace add bn-skn/claude-subteams
#   /plugin install claude-subteams@articortex
#
# This script is a convenience wrapper for shell environments.
# Prerequisite for private-repo access: gh auth login && gh auth setup-git
# (or set GITHUB_TOKEN in your environment).

set -euo pipefail

# --- Safety checks ------------------------------------------------------------

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "[claude-subteams] ERROR: \$HOME is unset or root. Aborting." >&2
  exit 1
fi

MARKETPLACE_NAME="articortex"
PLUGIN_NAME="claude-subteams"
REPO="bn-skn/claude-subteams"

echo "[claude-subteams] Installing..."

# --- Check dependencies -------------------------------------------------------

if ! command -v claude &>/dev/null; then
  echo "[claude-subteams] ERROR: 'claude' CLI not found on PATH." >&2
  echo "  Install Claude Code CLI first: https://docs.anthropic.com/en/docs/claude-code" >&2
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "[claude-subteams] ERROR: 'git' is required for marketplace cloning." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "[claude-subteams] WARNING: jq not found. Plugin hooks require jq to parse JSON."
  echo "  Install: apt install jq / brew install jq / apk add jq"
fi

# --- Add marketplace (idempotent) ---------------------------------------------

echo "[claude-subteams] Registering marketplace '$MARKETPLACE_NAME'..."

# Check if already added; tolerate non-zero from 'list' gracefully.
ALREADY_ADDED=false
if claude plugin marketplace list 2>/dev/null | grep -qF "$MARKETPLACE_NAME"; then
  ALREADY_ADDED=true
  echo "[claude-subteams] Marketplace '$MARKETPLACE_NAME' already registered — skipping add."
fi

if [ "$ALREADY_ADDED" = false ]; then
  # NOTE: verify exact subcommand against 'claude plugin marketplace --help'
  # if this fails with "unknown command", the CLI version may differ.
  if ! claude plugin marketplace add "$REPO"; then
    echo "[claude-subteams] ERROR: marketplace add failed." >&2
    echo "  This is a PRIVATE repo — configure GitHub auth first:" >&2
    echo "    gh auth login && gh auth setup-git   (or export GITHUB_TOKEN)" >&2
    exit 1
  fi
fi

# --- Install plugin (idempotent) ----------------------------------------------

PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE_NAME}"
if claude plugin list 2>/dev/null | grep -qF "$PLUGIN_KEY"; then
  echo "[claude-subteams] Plugin '$PLUGIN_KEY' already installed — skipping."
else
  echo "[claude-subteams] Installing plugin $PLUGIN_KEY..."
  # NOTE: verify exact subcommand against 'claude plugin --help' if this fails.
  claude plugin install "$PLUGIN_KEY"
fi

# --- Warn about superpowers conflict ------------------------------------------

# Best-effort check across settings.json and installed_plugins.json (non-fatal).
if grep -qs '"superpowers@claude-plugins-official": true' \
     "$HOME/.claude/settings.json" \
     "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; then
  echo ""
  echo "[claude-subteams] WARNING: The 'superpowers' plugin appears to be enabled."
  echo "  claude-subteams replaces superpowers methodology."
  echo "  Running both may cause conflicts."
  echo "  To disable: remove 'superpowers@claude-plugins-official' from ~/.claude/settings.json"
fi

# --- CLAUDE.md snippet (interactive only) -------------------------------------

if [ -t 0 ]; then
  echo ""
  if [ -f "CLAUDE.md" ] && grep -q "claude-subteams" "CLAUDE.md" 2>/dev/null; then
    echo "[claude-subteams] Activation snippet already in ./CLAUDE.md — skipping."
  elif [ -f "CLAUDE.md" ]; then
    read -r -p "[claude-subteams] Add activation snippet to ./CLAUDE.md? [y/N] " ADD_SNIPPET
    if [[ "${ADD_SNIPPET,,}" == "y" ]]; then
      # Snippet is embedded here — no dependency on the installed plugin tree path.
      cat >> "CLAUDE.md" << 'SNIPPET'

## Development Methodology

For development tasks use the claude-subteams plugin (orchestrator + 12 specialized agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent.
SNIPPET
      echo "[claude-subteams] Snippet appended to ./CLAUDE.md."
    fi
  else
    echo "[claude-subteams] No CLAUDE.md in current directory — snippet not added."
    echo "  Add it manually later. See README.md for the snippet."
  fi
fi

# --- Done ---------------------------------------------------------------------

echo ""
echo "[claude-subteams] Done. Restart Claude Code (/reload-plugins or new session)."
