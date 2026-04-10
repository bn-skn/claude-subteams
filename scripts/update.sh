#!/bin/bash
# Update claude-subteams plugin

set -euo pipefail

PLUGIN_DIR="$HOME/.claude/plugins/claude-subteams"

echo "[claude-subteams] Updating..."

# --- Verify install -------------------------------------------------------

if [ ! -d "$PLUGIN_DIR/.git" ]; then
  echo "[claude-subteams] ERROR: $PLUGIN_DIR is not a git repository."
  echo "  Re-run install.sh to perform a fresh installation."
  exit 1
fi

# --- Capture current version info -----------------------------------------

BEFORE_SHA=$(git -C "$PLUGIN_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
BEFORE_SKILLS=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')

# Check plugin.json for version field
BEFORE_VERSION=""
if [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
  if command -v node &>/dev/null; then
    BEFORE_VERSION=$(node -e "
      try {
        const p = require('$PLUGIN_DIR/.claude-plugin/plugin.json');
        process.stdout.write(p.version || '');
      } catch(e) {}
    " 2>/dev/null || true)
  elif command -v python3 &>/dev/null; then
    BEFORE_VERSION=$(python3 -c "
import json
try:
    with open('$PLUGIN_DIR/.claude-plugin/plugin.json') as f:
        print(json.load(f).get('version', ''), end='')
except: pass
" 2>/dev/null || true)
  fi
fi

# --- Pull -----------------------------------------------------------------

echo "[claude-subteams] Pulling origin/main..."
git -C "$PLUGIN_DIR" fetch origin
REMOTE_SHA=$(git -C "$PLUGIN_DIR" rev-parse origin/main)

if [ "$BEFORE_SHA" = "$REMOTE_SHA" ]; then
  echo "[claude-subteams] Already up to date ($(git -C "$PLUGIN_DIR" log -1 --format='%h %s'))."
  exit 0
fi

git -C "$PLUGIN_DIR" pull origin main

# --- Compare versions -----------------------------------------------------

AFTER_SHA=$(git -C "$PLUGIN_DIR" rev-parse HEAD)
AFTER_VERSION=""
if [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
  if command -v node &>/dev/null; then
    AFTER_VERSION=$(node -e "
      try {
        const p = require('$PLUGIN_DIR/.claude-plugin/plugin.json');
        process.stdout.write(p.version || '');
      } catch(e) {}
    " 2>/dev/null || true)
  elif command -v python3 &>/dev/null; then
    AFTER_VERSION=$(python3 -c "
import json
try:
    with open('$PLUGIN_DIR/.claude-plugin/plugin.json') as f:
        print(json.load(f).get('version', ''), end='')
except: pass
" 2>/dev/null || true)
  fi
fi

if [ -n "$BEFORE_VERSION" ] && [ -n "$AFTER_VERSION" ] && [ "$BEFORE_VERSION" != "$AFTER_VERSION" ]; then
  echo "[claude-subteams] Version: $BEFORE_VERSION → $AFTER_VERSION"
elif [ -n "$AFTER_VERSION" ]; then
  echo "[claude-subteams] Version: $AFTER_VERSION (SHA $BEFORE_SHA → $AFTER_SHA)"
fi

# --- Report new/changed skills --------------------------------------------

AFTER_SKILLS=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "[claude-subteams] Skills: $BEFORE_SKILLS → $AFTER_SKILLS"

# List skills changed in this update
CHANGED=$(git -C "$PLUGIN_DIR" diff --name-only "$BEFORE_SHA" HEAD -- skills/ 2>/dev/null || true)
if [ -n "$CHANGED" ]; then
  echo "[claude-subteams] Changed skill files:"
  echo "$CHANGED" | while read -r line; do
    echo "  $line"
  done
fi

echo ""
echo "[claude-subteams] Update complete. Restart Claude Code to apply changes."
