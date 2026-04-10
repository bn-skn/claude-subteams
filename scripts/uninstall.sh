#!/bin/bash
# Uninstall claude-subteams plugin

set -euo pipefail

PLUGIN_DIR="$HOME/.claude/plugins/claude-subteams"
SETTINGS="$HOME/.claude/settings.json"

echo "[claude-subteams] Uninstalling..."

# --- Remove from settings.json --------------------------------------------

if [ -f "$SETTINGS" ]; then
  if grep -q '"claude-subteams"' "$SETTINGS" 2>/dev/null; then
    if command -v node &>/dev/null; then
      node -e "
        const fs = require('fs');
        const s = JSON.parse(fs.readFileSync('$SETTINGS', 'utf8'));
        s.enabledPlugins = (s.enabledPlugins || []).filter(p => p !== 'claude-subteams');
        fs.writeFileSync('$SETTINGS', JSON.stringify(s, null, 2) + '\n');
      "
    elif command -v python3 &>/dev/null; then
      python3 - <<'PYEOF'
import json
path = '$SETTINGS'
with open(path) as f:
    s = json.load(f)
s['enabledPlugins'] = [p for p in s.get('enabledPlugins', []) if p != 'claude-subteams']
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
PYEOF
    else
      echo "[claude-subteams] WARNING: Neither node nor python3 found."
      echo "  Remove claude-subteams from enabledPlugins in $SETTINGS manually."
    fi
    echo "[claude-subteams] Removed from enabledPlugins in settings.json."
  else
    echo "[claude-subteams] Not found in settings.json — nothing to remove."
  fi
else
  echo "[claude-subteams] settings.json not found — nothing to update."
fi

# --- Remove plugin directory ----------------------------------------------

if [ -d "$PLUGIN_DIR" ]; then
  read -r -p "[claude-subteams] Remove $PLUGIN_DIR? [y/N] " ANSWER
  if [[ "${ANSWER,,}" == "y" ]]; then
    rm -rf "$PLUGIN_DIR"
    echo "[claude-subteams] Plugin directory removed."
  else
    echo "[claude-subteams] Plugin directory kept at $PLUGIN_DIR."
  fi
else
  echo "[claude-subteams] Plugin directory not found — nothing to remove."
fi

echo ""
echo "[claude-subteams] Uninstall complete."
echo "  Note: Project-level files (BACKLOG.md, ARCHITECTURE.md, CONVENTIONS.md, etc.)"
echo "  were NOT removed. Delete them manually if you no longer need them."
echo ""
echo "  Restart Claude Code for changes to take effect."
