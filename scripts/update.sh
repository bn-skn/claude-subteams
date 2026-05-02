#!/bin/bash
# Update claude-subteams plugin

set -euo pipefail

MARKETPLACE="claude-subteams"
PLUGIN_NAME="claude-subteams"
PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/$MARKETPLACE/plugins/$PLUGIN_NAME"

echo "[claude-subteams] Updating..."

# --- Check old path and migrate if needed ------------------------------------

OLD_DIR="$HOME/.claude/plugins/claude-subteams"
if [ -d "$OLD_DIR/.git" ] && [ ! -d "$PLUGIN_DIR" ]; then
  echo "[claude-subteams] Found old install at $OLD_DIR — migrating..."
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  mv "$OLD_DIR" "$PLUGIN_DIR"
  echo "[claude-subteams] Migrated to $PLUGIN_DIR."
fi

# --- Verify install -----------------------------------------------------------

if [ ! -d "$PLUGIN_DIR/.git" ]; then
  echo "[claude-subteams] ERROR: $PLUGIN_DIR is not a git repository."
  echo "  Re-run install.sh to perform a fresh installation."
  exit 1
fi

# --- Capture current version info ---------------------------------------------

BEFORE_SHA=$(git -C "$PLUGIN_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
BEFORE_SKILLS=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')

BEFORE_VERSION=""
if [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
  if command -v node &>/dev/null; then
    BEFORE_VERSION=$(PJSON="$PLUGIN_DIR/.claude-plugin/plugin.json" node -e '
      try { process.stdout.write(require(process.env.PJSON).version || ""); } catch(e) {}
    ' 2>/dev/null || true)
  elif command -v python3 &>/dev/null; then
    BEFORE_VERSION=$(PJSON="$PLUGIN_DIR/.claude-plugin/plugin.json" python3 -c '
import json, os
try:
    with open(os.environ["PJSON"]) as f:
        print(json.load(f).get("version", ""), end="")
except: pass
' 2>/dev/null || true)
  fi
fi

# --- Pull ---------------------------------------------------------------------

echo "[claude-subteams] Pulling origin/main..."
git -C "$PLUGIN_DIR" fetch origin
REMOTE_SHA=$(git -C "$PLUGIN_DIR" rev-parse origin/main)

if [ "$BEFORE_SHA" = "$REMOTE_SHA" ]; then
  echo "[claude-subteams] Already up to date ($(git -C "$PLUGIN_DIR" log -1 --format='%h %s'))."
  exit 0
fi

git -C "$PLUGIN_DIR" pull origin main --ff-only

# --- Compare versions ---------------------------------------------------------

AFTER_SHA=$(git -C "$PLUGIN_DIR" rev-parse HEAD)
AFTER_VERSION=""
if [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
  if command -v node &>/dev/null; then
    AFTER_VERSION=$(PJSON="$PLUGIN_DIR/.claude-plugin/plugin.json" node -e '
      try { process.stdout.write(require(process.env.PJSON).version || ""); } catch(e) {}
    ' 2>/dev/null || true)
  elif command -v python3 &>/dev/null; then
    AFTER_VERSION=$(PJSON="$PLUGIN_DIR/.claude-plugin/plugin.json" python3 -c '
import json, os
try:
    with open(os.environ["PJSON"]) as f:
        print(json.load(f).get("version", ""), end="")
except: pass
' 2>/dev/null || true)
  fi
fi

if [ -n "$BEFORE_VERSION" ] && [ -n "$AFTER_VERSION" ] && [ "$BEFORE_VERSION" != "$AFTER_VERSION" ]; then
  echo "[claude-subteams] Version: $BEFORE_VERSION -> $AFTER_VERSION"
elif [ -n "$AFTER_VERSION" ]; then
  echo "[claude-subteams] Version: $AFTER_VERSION (SHA $BEFORE_SHA -> $AFTER_SHA)"
fi

# --- Report new/changed skills ------------------------------------------------

AFTER_SKILLS=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "[claude-subteams] Skills: $BEFORE_SKILLS -> $AFTER_SKILLS"

CHANGED=$(git -C "$PLUGIN_DIR" diff --name-only "$BEFORE_SHA" HEAD -- skills/ 2>/dev/null || true)
if [ -n "$CHANGED" ]; then
  echo "[claude-subteams] Changed skill files:"
  echo "$CHANGED" | while read -r line; do
    echo "  $line"
  done
fi

echo ""
echo "[claude-subteams] Update complete. Restart Claude Code to apply changes (/reload-plugins or new session)."
