#!/bin/bash
# Uninstall claude-subteams plugin

set -euo pipefail

# --- Safety checks ------------------------------------------------------------

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "[claude-subteams] ERROR: \$HOME is unset or root. Aborting." >&2
  exit 1
fi

MARKETPLACE="bn-skn"
PLUGIN_NAME="claude-subteams"
PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/$MARKETPLACE/plugins/$PLUGIN_NAME"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/$MARKETPLACE"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
KNOWN_MARKETPLACES="$HOME/.claude/plugins/known_marketplaces.json"
SETTINGS="$HOME/.claude/settings.json"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE}"

echo "[claude-subteams] Uninstalling..."

# --- Remove from settings.json (enabledPlugins) ------------------------------

if [ -f "$SETTINGS" ]; then
  # Remove both current and old keys
  for KEY in "$PLUGIN_KEY" "claude-subteams@claude-subteams"; do
    if grep -q "\"$KEY\"" "$SETTINGS" 2>/dev/null; then
      if command -v node &>/dev/null; then
        KEY_VAL="$KEY" SETTINGS_FILE="$SETTINGS" \
        node -e '
          const fs = require("fs");
          const path = process.env.SETTINGS_FILE;
          const key = process.env.KEY_VAL;
          const s = JSON.parse(fs.readFileSync(path, "utf8"));
          if (s.enabledPlugins) delete s.enabledPlugins[key];
          fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
        '
      elif command -v python3 &>/dev/null; then
        KEY_VAL="$KEY" SETTINGS_FILE="$SETTINGS" \
        python3 -c '
import json, os
path = os.environ["SETTINGS_FILE"]
key = os.environ["KEY_VAL"]
with open(path) as f:
    s = json.load(f)
s.get("enabledPlugins", {}).pop(key, None)
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
      else
        echo "[claude-subteams] WARNING: Neither node nor python3 found."
        echo "  Remove \"$KEY\" from enabledPlugins in $SETTINGS manually."
      fi
    fi
  done
  echo "[claude-subteams] Removed from enabledPlugins in settings.json."
fi

# --- Remove from installed_plugins.json --------------------------------------

if [ -f "$INSTALLED_PLUGINS" ]; then
  for KEY in "$PLUGIN_KEY" "claude-subteams@claude-subteams"; do
    if grep -q "\"$KEY\"" "$INSTALLED_PLUGINS" 2>/dev/null; then
      if command -v node &>/dev/null; then
        KEY_VAL="$KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" \
        node -e '
          const fs = require("fs");
          const path = process.env.PLUGINS_FILE;
          const key = process.env.KEY_VAL;
          const s = JSON.parse(fs.readFileSync(path, "utf8"));
          if (s.plugins) delete s.plugins[key];
          fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
        '
      elif command -v python3 &>/dev/null; then
        KEY_VAL="$KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" \
        python3 -c '
import json, os
path = os.environ["PLUGINS_FILE"]
key = os.environ["KEY_VAL"]
with open(path) as f:
    s = json.load(f)
s.get("plugins", {}).pop(key, None)
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
      else
        echo "[claude-subteams] WARNING: Neither node nor python3 found."
        echo "  Remove \"$KEY\" from $INSTALLED_PLUGINS manually."
      fi
    fi
  done
  echo "[claude-subteams] Removed from installed_plugins.json."
fi

# --- Remove from known_marketplaces.json -------------------------------------

if [ -f "$KNOWN_MARKETPLACES" ]; then
  for MKT in "$MARKETPLACE" "claude-subteams"; do
    if grep -q "\"$MKT\"" "$KNOWN_MARKETPLACES" 2>/dev/null; then
      if command -v node &>/dev/null; then
        MKT_VAL="$MKT" MKT_FILE="$KNOWN_MARKETPLACES" \
        node -e '
          const fs = require("fs");
          const path = process.env.MKT_FILE;
          const key = process.env.MKT_VAL;
          const s = JSON.parse(fs.readFileSync(path, "utf8"));
          delete s[key];
          fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
        '
      fi
    fi
  done
  echo "[claude-subteams] Removed from known_marketplaces.json."
fi

# --- Remove plugin and marketplace directories --------------------------------

if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-y" ]; then
  ANSWER="y"
elif [ -t 0 ]; then
  read -r -p "[claude-subteams] Remove plugin directory? [y/N] " ANSWER
else
  ANSWER="y"
fi

if [[ "${ANSWER,,}" == "y" ]]; then
  # Remove current path
  [ -d "$PLUGIN_DIR" ] && rm -rf "$PLUGIN_DIR"
  # Remove marketplace wrapper if empty
  if [ -d "$MARKETPLACE_DIR" ]; then
    REMAINING=$(find "$MARKETPLACE_DIR/plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
      rm -rf "$MARKETPLACE_DIR"
    fi
  fi
  # Remove old paths
  [ -d "$HOME/.claude/plugins/marketplaces/claude-subteams" ] && rm -rf "$HOME/.claude/plugins/marketplaces/claude-subteams"
  [ -d "$HOME/.claude/plugins/claude-subteams" ] && rm -rf "$HOME/.claude/plugins/claude-subteams"
  echo "[claude-subteams] Plugin directory removed."
else
  echo "[claude-subteams] Plugin directory kept."
fi

echo ""
echo "[claude-subteams] Uninstall complete."
echo "  Note: Project-level files (BACKLOG.md, CONVENTIONS.md, etc.) were NOT removed."
echo "  Also remove the snippet from your CLAUDE.md if you added it."
echo "  Restart Claude Code for changes to take effect."
