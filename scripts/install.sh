#!/bin/bash
# Install claude-subteams plugin for Claude Code
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/bn-skn/claude-subteams/main/scripts/install.sh)
#
# Or clone first:
#   git clone https://github.com/bn-skn/claude-subteams /tmp/claude-subteams
#   bash /tmp/claude-subteams/scripts/install.sh

set -euo pipefail

MARKETPLACE="claude-subteams"
PLUGIN_NAME="claude-subteams"
PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/$MARKETPLACE/plugins/$PLUGIN_NAME"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
SETTINGS="$HOME/.claude/settings.json"
REPO_URL="https://github.com/bn-skn/claude-subteams"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE}"

echo "[claude-subteams] Installing..."

# --- Clone or update ------------------------------------------------------

if [ -d "$PLUGIN_DIR/.git" ]; then
  echo "[claude-subteams] Already installed — pulling latest..."
  git -C "$PLUGIN_DIR" pull origin main --ff-only 2>/dev/null || echo "[claude-subteams] Pull failed, using existing version."
elif [ -d "$PLUGIN_DIR" ]; then
  echo "[claude-subteams] Directory exists but is not a git repo — skipping clone."
else
  echo "[claude-subteams] Cloning from $REPO_URL..."
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  git clone "$REPO_URL" "$PLUGIN_DIR"
fi

# --- Clean up old install path (if exists) --------------------------------

OLD_DIR="$HOME/.claude/plugins/claude-subteams"
if [ -d "$OLD_DIR" ] && [ "$OLD_DIR" != "$PLUGIN_DIR" ]; then
  echo "[claude-subteams] Removing old install at $OLD_DIR..."
  rm -rf "$OLD_DIR"
fi

# --- Register in installed_plugins.json -----------------------------------

if [ ! -f "$INSTALLED_PLUGINS" ]; then
  echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS"
fi

if command -v node &>/dev/null; then
  PLUGIN_DIR_VAL="$PLUGIN_DIR" PLUGIN_KEY_VAL="$PLUGIN_KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" \
  node -e '
    const fs = require("fs");
    const path = process.env.PLUGINS_FILE;
    const key = process.env.PLUGIN_KEY_VAL;
    const dir = process.env.PLUGIN_DIR_VAL;
    const s = JSON.parse(fs.readFileSync(path, "utf8"));
    if (!s.plugins) s.plugins = {};
    const now = new Date().toISOString();
    if (!s.plugins[key] || !Array.isArray(s.plugins[key]) || s.plugins[key].length === 0) {
      s.plugins[key] = [{ scope: "user", installPath: dir, version: "1.0.0", installedAt: now, lastUpdated: now }];
      console.log("[claude-subteams] Registered in installed_plugins.json.");
    } else {
      s.plugins[key][0].lastUpdated = now;
      console.log("[claude-subteams] Already registered — updated timestamp.");
    }
    fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
  '
elif command -v python3 &>/dev/null; then
  PLUGIN_DIR_VAL="$PLUGIN_DIR" PLUGIN_KEY_VAL="$PLUGIN_KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" \
  python3 -c '
import json, os
from datetime import datetime, timezone
path = os.environ["PLUGINS_FILE"]
key = os.environ["PLUGIN_KEY_VAL"]
d = os.environ["PLUGIN_DIR_VAL"]
with open(path) as f:
    s = json.load(f)
s.setdefault("plugins", {})
now = datetime.now(timezone.utc).isoformat()
if key not in s["plugins"] or not isinstance(s["plugins"][key], list) or len(s["plugins"][key]) == 0:
    s["plugins"][key] = [{"scope": "user", "installPath": d, "version": "1.0.0", "installedAt": now, "lastUpdated": now}]
    print("[claude-subteams] Registered in installed_plugins.json.")
else:
    s["plugins"][key][0]["lastUpdated"] = now
    print("[claude-subteams] Already registered — updated timestamp.")
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
else
  echo "[claude-subteams] WARNING: Neither node nor python3 found."
  echo "  See INSTALL.md for manual registration steps."
fi

# --- Add to settings.json enabledPlugins ----------------------------------

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

if ! grep -q "\"$PLUGIN_KEY\"" "$SETTINGS" 2>/dev/null; then
  if command -v node &>/dev/null; then
    PLUGIN_KEY_VAL="$PLUGIN_KEY" SETTINGS_FILE="$SETTINGS" \
    node -e '
      const fs = require("fs");
      const path = process.env.SETTINGS_FILE;
      const key = process.env.PLUGIN_KEY_VAL;
      const s = JSON.parse(fs.readFileSync(path, "utf8"));
      if (!s.enabledPlugins) s.enabledPlugins = {};
      s.enabledPlugins[key] = true;
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
s.setdefault("enabledPlugins", {})
s["enabledPlugins"][key] = True
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
  fi
  echo "[claude-subteams] Added to enabledPlugins in settings.json."
else
  echo "[claude-subteams] Already enabled in settings.json."
fi

# --- Warn about superpowers conflict --------------------------------------

if grep -q '"superpowers@claude-plugins-official": true' "$SETTINGS" 2>/dev/null; then
  echo ""
  echo "[claude-subteams] WARNING: The 'superpowers' plugin is enabled."
  echo "  claude-subteams replaces superpowers methodology."
  echo "  Running both may cause conflicts."
  # Use /dev/tty for interactive input (works even when piped via curl)
  if [ -t 0 ] || [ -e /dev/tty ]; then
    read -r -p "  Disable superpowers now? [y/N] " ANSWER </dev/tty 2>/dev/null || ANSWER="N"
    if [[ "${ANSWER,,}" == "y" ]]; then
      if command -v node &>/dev/null; then
        SETTINGS_FILE="$SETTINGS" node -e '
          const fs = require("fs");
          const path = process.env.SETTINGS_FILE;
          const s = JSON.parse(fs.readFileSync(path, "utf8"));
          if (s.enabledPlugins) delete s.enabledPlugins["superpowers@claude-plugins-official"];
          fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
        '
      elif command -v python3 &>/dev/null; then
        SETTINGS_FILE="$SETTINGS" python3 -c '
import json, os
path = os.environ["SETTINGS_FILE"]
with open(path) as f:
    s = json.load(f)
s.get("enabledPlugins", {}).pop("superpowers@claude-plugins-official", None)
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
      fi
      echo "[claude-subteams] superpowers disabled."
    else
      echo "[claude-subteams] superpowers kept."
    fi
  else
    echo "  Run the script interactively to disable superpowers."
  fi
fi

# --- Verify ---------------------------------------------------------------

echo ""
SKILL_COUNT=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$PLUGIN_DIR/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
HOOK_COUNT=$(find "$PLUGIN_DIR/hooks" -maxdepth 1 -type f -not -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
echo "[claude-subteams] Installed:"
echo "  Skills : $SKILL_COUNT"
echo "  Agents : $AGENT_COUNT"
echo "  Hooks  : $HOOK_COUNT"
echo "  Path   : $PLUGIN_DIR"

if [ "$SKILL_COUNT" -lt 40 ]; then
  echo ""
  echo "[claude-subteams] WARNING: Expected 46 skills, found $SKILL_COUNT."
  echo "  The plugin may not work correctly. See INSTALL.md for troubleshooting."
fi

# --- CLAUDE.md snippet (interactive only) ---------------------------------

if [ -t 0 ] || [ -e /dev/tty ]; then
  echo ""
  read -r -p "[claude-subteams] Add activation snippet to ./CLAUDE.md? [y/N] " ADD_SNIPPET </dev/tty 2>/dev/null || ADD_SNIPPET="N"
  if [[ "${ADD_SNIPPET,,}" == "y" ]]; then
    SNIPPET_FILE="$PLUGIN_DIR/templates/claudemd-snippet.md"
    if [ -f "$SNIPPET_FILE" ]; then
      echo "" >> "CLAUDE.md"
      cat "$SNIPPET_FILE" >> "CLAUDE.md"
      echo "[claude-subteams] Snippet appended to ./CLAUDE.md."
    else
      echo "[claude-subteams] WARNING: Snippet template not found."
    fi
  fi
fi

echo ""
echo "[claude-subteams] Done. Restart Claude Code (/reload-plugins or new session)."
