#!/bin/bash
# Install claude-subteams plugin

set -euo pipefail

PLUGIN_DIR="$HOME/.claude/plugins/claude-subteams"
SETTINGS="$HOME/.claude/settings.json"
REPO_URL="https://github.com/bnskn/claude-subteams"

echo "[claude-subteams] Installing..."

# --- Clone or copy --------------------------------------------------------

if [ -d "$PLUGIN_DIR/.git" ]; then
  echo "[claude-subteams] Already installed at $PLUGIN_DIR — pulling latest..."
  git -C "$PLUGIN_DIR" pull origin main
elif [ -d "$PLUGIN_DIR" ]; then
  echo "[claude-subteams] Directory exists but is not a git repo — skipping clone."
else
  echo "[claude-subteams] Cloning from $REPO_URL..."
  mkdir -p "$HOME/.claude/plugins"
  git clone "$REPO_URL" "$PLUGIN_DIR"
fi

# --- Add to settings.json enabledPlugins ----------------------------------

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Check if already enabled
if grep -q '"claude-subteams"' "$SETTINGS" 2>/dev/null; then
  echo "[claude-subteams] Already listed in settings.json."
else
  # Use node if available for safe JSON mutation; fall back to Python
  if command -v node &>/dev/null; then
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync('$SETTINGS', 'utf8'));
      s.enabledPlugins = s.enabledPlugins || [];
      if (!s.enabledPlugins.includes('claude-subteams')) {
        s.enabledPlugins.push('claude-subteams');
      }
      fs.writeFileSync('$SETTINGS', JSON.stringify(s, null, 2) + '\n');
    "
  elif command -v python3 &>/dev/null; then
    python3 - <<PYEOF
import json, sys
path = '$SETTINGS'
with open(path) as f:
    s = json.load(f)
s.setdefault('enabledPlugins', [])
if 'claude-subteams' not in s['enabledPlugins']:
    s['enabledPlugins'].append('claude-subteams')
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
PYEOF
  else
    echo "[claude-subteams] WARNING: Neither node nor python3 found. Add claude-subteams to enabledPlugins in $SETTINGS manually."
  fi
  echo "[claude-subteams] Added to enabledPlugins in settings.json."
fi

# --- Warn about superpowers conflict --------------------------------------

if grep -q '"superpowers"' "$SETTINGS" 2>/dev/null; then
  echo ""
  echo "[claude-subteams] WARNING: The 'superpowers' plugin is enabled."
  echo "  claude-subteams provides its own methodology (brainstorming, plans, dispatch)."
  echo "  Running both together may cause conflicts or redundant prompts."
  echo ""
  read -r -p "  Disable superpowers now? [y/N] " ANSWER
  if [[ "${ANSWER,,}" == "y" ]]; then
    if command -v node &>/dev/null; then
      node -e "
        const fs = require('fs');
        const s = JSON.parse(fs.readFileSync('$SETTINGS', 'utf8'));
        s.enabledPlugins = (s.enabledPlugins || []).filter(p => p !== 'superpowers');
        fs.writeFileSync('$SETTINGS', JSON.stringify(s, null, 2) + '\n');
      "
    elif command -v python3 &>/dev/null; then
      python3 - <<PYEOF
import json
path = '$SETTINGS'
with open(path) as f:
    s = json.load(f)
s['enabledPlugins'] = [p for p in s.get('enabledPlugins', []) if p != 'superpowers']
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
PYEOF
    fi
    echo "[claude-subteams] superpowers disabled."
  else
    echo "[claude-subteams] superpowers kept. You can disable it manually in $SETTINGS."
  fi
fi

# --- Verify installation --------------------------------------------------

echo ""
SKILL_COUNT=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$PLUGIN_DIR/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
echo "[claude-subteams] Verification:"
echo "  Skills  : $SKILL_COUNT"
echo "  Agents  : $AGENT_COUNT"

# --- Recommended MCP servers ----------------------------------------------

echo ""
echo "[claude-subteams] Recommended MCP servers (not required, but improve research tasks):"
echo "  - context7      : https://github.com/upstash/context7"
echo "  - playwright    : https://github.com/microsoft/playwright-mcp"
echo "  - github        : https://github.com/github/github-mcp-server"

# --- Offer to add CLAUDE.md snippet -----------------------------------------

echo ""
SNIPPET_FILE="$PLUGIN_DIR/templates/claudemd-snippet.md"
CLAUDEMD="CLAUDE.md"

read -r -p "[claude-subteams] Would you like to add the claude-subteams snippet to your CLAUDE.md? [y/N] " ADD_SNIPPET
if [[ "${ADD_SNIPPET,,}" == "y" ]]; then
  if [ -f "$SNIPPET_FILE" ]; then
    echo "" >> "$CLAUDEMD"
    cat "$SNIPPET_FILE" >> "$CLAUDEMD"
    echo "[claude-subteams] Snippet appended to $CLAUDEMD."
  else
    echo "[claude-subteams] WARNING: Snippet template not found at $SNIPPET_FILE."
  fi
else
  echo "[claude-subteams] You can add it manually later from templates/claudemd-snippet.md"
fi

echo ""
echo "[claude-subteams] Installation complete. Restart Claude Code to activate."
