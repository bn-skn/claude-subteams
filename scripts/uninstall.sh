#!/bin/bash
# Uninstall claude-subteams plugin

set -euo pipefail

# --- Safety checks ------------------------------------------------------------

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "[claude-subteams] ERROR: \$HOME is unset or root. Aborting." >&2
  exit 1
fi

MARKETPLACE="claude-subteams"
PLUGIN_NAME="claude-subteams"
PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/$MARKETPLACE/plugins/$PLUGIN_NAME"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
SETTINGS="$HOME/.claude/settings.json"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE}"

echo "[claude-subteams] Uninstalling..."

# --- Remove from settings.json (enabledPlugins) ------------------------------

if [ -f "$SETTINGS" ]; then
  if grep -q "\"$PLUGIN_KEY\"" "$SETTINGS" 2>/dev/null; then
    if command -v node &>/dev/null; then
      PLUGIN_KEY_VAL="$PLUGIN_KEY" SETTINGS_FILE="$SETTINGS" \
      node -e '
        const fs = require("fs");
        const path = process.env.SETTINGS_FILE;
        const key = process.env.PLUGIN_KEY_VAL;
        const s = JSON.parse(fs.readFileSync(path, "utf8"));
        if (s.enabledPlugins) delete s.enabledPlugins[key];
        fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
      '
    elif command -v python3 &>/dev/null; then
      PLUGIN_KEY_VAL="$PLUGIN_KEY" SETTINGS_FILE="$SETTINGS" \
      python3 -c '
import json, os
path = os.environ["SETTINGS_FILE"]
key = os.environ["PLUGIN_KEY_VAL"]
with open(path) as f:
    s = json.load(f)
s.get("enabledPlugins", {}).pop(key, None)
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
    else
      echo "[claude-subteams] WARNING: Neither node nor python3 found."
      echo "  Remove \"$PLUGIN_KEY\" from enabledPlugins in $SETTINGS manually."
    fi
    echo "[claude-subteams] Removed from enabledPlugins in settings.json."
  else
    echo "[claude-subteams] Not found in settings.json — nothing to remove."
  fi
else
  echo "[claude-subteams] settings.json not found — nothing to update."
fi

# --- Remove from installed_plugins.json --------------------------------------

if [ -f "$INSTALLED_PLUGINS" ]; then
  if grep -q "\"$PLUGIN_KEY\"" "$INSTALLED_PLUGINS" 2>/dev/null; then
    if command -v node &>/dev/null; then
      PLUGIN_KEY_VAL="$PLUGIN_KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" \
      node -e '
        const fs = require("fs");
        const path = process.env.PLUGINS_FILE;
        const key = process.env.PLUGIN_KEY_VAL;
        const s = JSON.parse(fs.readFileSync(path, "utf8"));
        if (s.plugins) delete s.plugins[key];
        fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
      '
    elif command -v python3 &>/dev/null; then
      PLUGIN_KEY_VAL="$PLUGIN_KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" \
      python3 -c '
import json, os
path = os.environ["PLUGINS_FILE"]
key = os.environ["PLUGIN_KEY_VAL"]
with open(path) as f:
    s = json.load(f)
s.get("plugins", {}).pop(key, None)
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
    else
      echo "[claude-subteams] WARNING: Neither node nor python3 found."
      echo "  Remove \"$PLUGIN_KEY\" from $INSTALLED_PLUGINS manually."
    fi
    echo "[claude-subteams] Removed from installed_plugins.json."
  else
    echo "[claude-subteams] Not found in installed_plugins.json."
  fi
fi

# --- Remove plugin directory --------------------------------------------------

if [ -d "$PLUGIN_DIR" ]; then
  if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-y" ]; then
    ANSWER="y"
  elif [ -t 0 ]; then
    read -r -p "[claude-subteams] Remove $PLUGIN_DIR? [y/N] " ANSWER
  else
    ANSWER="y"
  fi
  if [[ "${ANSWER,,}" == "y" ]]; then
    rm -rf "$PLUGIN_DIR"
    echo "[claude-subteams] Plugin directory removed."
    # Clean up empty parent dirs
    rmdir "$HOME/.claude/plugins/marketplaces/$MARKETPLACE/plugins" 2>/dev/null || true
    rmdir "$HOME/.claude/plugins/marketplaces/$MARKETPLACE" 2>/dev/null || true
  else
    echo "[claude-subteams] Plugin directory kept at $PLUGIN_DIR."
  fi
else
  echo "[claude-subteams] Plugin directory not found at $PLUGIN_DIR — nothing to remove."
fi

# --- Clean up old install path (if exists) ------------------------------------

OLD_DIR="$HOME/.claude/plugins/claude-subteams"
if [ -d "$OLD_DIR" ]; then
  echo "[claude-subteams] Found old install at $OLD_DIR — removing..."
  rm -rf "$OLD_DIR"
fi

echo ""
echo "[claude-subteams] Uninstall complete."
echo "  Note: Project-level files (BACKLOG.md, CONVENTIONS.md, etc.) were NOT removed."
echo "  Also remove the snippet from your CLAUDE.md if you added it."
echo "  Restart Claude Code for changes to take effect."
