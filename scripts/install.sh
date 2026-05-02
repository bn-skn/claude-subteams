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
REPO_URL="https://github.com/bn-skn/claude-subteams"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE}"

echo "[claude-subteams] Installing..."

# --- Check dependencies -------------------------------------------------------

MISSING_DEPS=""
if ! command -v git &>/dev/null; then MISSING_DEPS="$MISSING_DEPS git"; fi
if ! command -v jq &>/dev/null; then
  echo "[claude-subteams] WARNING: jq not found. Plugin hooks require jq to parse JSON."
  echo "  Install: apt install jq / brew install jq / apk add jq"
fi
if ! command -v node &>/dev/null && ! command -v python3 &>/dev/null; then
  MISSING_DEPS="$MISSING_DEPS node-or-python3"
fi
if [ -n "$MISSING_DEPS" ]; then
  echo "[claude-subteams] ERROR: Missing required dependencies:$MISSING_DEPS" >&2
  exit 1
fi

# --- Clone or update ----------------------------------------------------------

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

# --- Read version from plugin.json -------------------------------------------

PLUGIN_VERSION="unknown"
if [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
  if command -v node &>/dev/null; then
    PLUGIN_VERSION=$(PJSON="$PLUGIN_DIR/.claude-plugin/plugin.json" node -e '
      const fs = require("fs");
      try { process.stdout.write(JSON.parse(fs.readFileSync(process.env.PJSON, "utf8")).version || "unknown"); } catch(e) { process.stdout.write("unknown"); }
    ' 2>/dev/null || echo "unknown")
  elif command -v python3 &>/dev/null; then
    PLUGIN_VERSION=$(PJSON="$PLUGIN_DIR/.claude-plugin/plugin.json" python3 -c '
import json, os
try:
    with open(os.environ["PJSON"]) as f:
        print(json.load(f).get("version", "unknown"), end="")
except: print("unknown", end="")
' 2>/dev/null || echo "unknown")
  fi
fi

# --- Create marketplace wrapper -----------------------------------------------

MARKETPLACE_JSON="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
if [ ! -f "$MARKETPLACE_JSON" ]; then
  mkdir -p "$MARKETPLACE_DIR/.claude-plugin"
  cat > "$MARKETPLACE_JSON" << MEOF
{
  "\$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "$MARKETPLACE",
  "description": "Local marketplace for claude-subteams plugin",
  "owner": {
    "name": "Bogdan",
    "url": "https://github.com/bn-skn"
  },
  "plugins": [
    {
      "name": "$PLUGIN_NAME",
      "description": "Orchestrator + 9 specialized sub-team agents with quality pipeline and SDLC hooks",
      "category": "development",
      "source": "./plugins/$PLUGIN_NAME",
      "homepage": "https://github.com/bn-skn/claude-subteams"
    }
  ]
}
MEOF
  echo "[claude-subteams] Created marketplace wrapper at $MARKETPLACE_DIR."
fi

# --- Register marketplace in known_marketplaces.json --------------------------

mkdir -p "$HOME/.claude/plugins"
if [ ! -f "$KNOWN_MARKETPLACES" ]; then
  echo '{}' > "$KNOWN_MARKETPLACES"
fi

if ! grep -qF "\"$MARKETPLACE\"" "$KNOWN_MARKETPLACES" 2>/dev/null; then
  if command -v node &>/dev/null; then
    MKT_NAME="$MARKETPLACE" MKT_DIR="$MARKETPLACE_DIR" MKT_FILE="$KNOWN_MARKETPLACES" \
    node -e '
      const fs = require("fs");
      const path = process.env.MKT_FILE;
      const name = process.env.MKT_NAME;
      const dir = process.env.MKT_DIR;
      const s = JSON.parse(fs.readFileSync(path, "utf8"));
      s[name] = {
        source: { source: "local", path: dir },
        installLocation: dir,
        lastUpdated: new Date().toISOString()
      };
      fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
    '
  elif command -v python3 &>/dev/null; then
    MKT_NAME="$MARKETPLACE" MKT_DIR="$MARKETPLACE_DIR" MKT_FILE="$KNOWN_MARKETPLACES" \
    python3 -c '
import json, os
from datetime import datetime, timezone
path = os.environ["MKT_FILE"]
name = os.environ["MKT_NAME"]
d = os.environ["MKT_DIR"]
with open(path) as f:
    s = json.load(f)
s[name] = {
    "source": {"source": "local", "path": d},
    "installLocation": d,
    "lastUpdated": datetime.now(timezone.utc).isoformat()
}
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
  fi
  echo "[claude-subteams] Registered marketplace in known_marketplaces.json."
else
  echo "[claude-subteams] Marketplace already registered."
fi

# --- Clean up old install paths -----------------------------------------------

# Old marketplace name (claude-subteams == plugin name, causes cache recursion bug)
OLD_MKT_DIR="$HOME/.claude/plugins/marketplaces/claude-subteams"
if [ -d "$OLD_MKT_DIR" ] && [ "$OLD_MKT_DIR" != "$MARKETPLACE_DIR" ] && [ -d "$PLUGIN_DIR/.git" ]; then
  echo "[claude-subteams] Migrating from old marketplace path..."
  rm -rf "$OLD_MKT_DIR"
  # Clean old marketplace from known_marketplaces.json
  if command -v node &>/dev/null; then
    MKT_FILE="$KNOWN_MARKETPLACES" node -e '
      const fs = require("fs");
      const path = process.env.MKT_FILE;
      const s = JSON.parse(fs.readFileSync(path, "utf8"));
      delete s["claude-subteams"];
      fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
    ' 2>/dev/null || true
  fi
fi

# Old flat install path
OLD_FLAT="$HOME/.claude/plugins/claude-subteams"
if [ -d "$OLD_FLAT" ]; then
  rm -rf "$OLD_FLAT"
fi

# Clean old enabledPlugins key
OLD_KEY="claude-subteams@claude-subteams"
if [ "$OLD_KEY" != "$PLUGIN_KEY" ] && grep -qF "\"$OLD_KEY\"" "$SETTINGS" 2>/dev/null; then
  if command -v node &>/dev/null; then
    OLD_KEY_VAL="$OLD_KEY" SETTINGS_FILE="$SETTINGS" node -e '
      const fs = require("fs");
      const path = process.env.SETTINGS_FILE;
      const key = process.env.OLD_KEY_VAL;
      const s = JSON.parse(fs.readFileSync(path, "utf8"));
      if (s.enabledPlugins) delete s.enabledPlugins[key];
      fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
    ' 2>/dev/null || true
  fi
  echo "[claude-subteams] Cleaned old enabledPlugins key."
fi

# Clean old installed_plugins key
if [ "$OLD_KEY" != "$PLUGIN_KEY" ] && grep -qF "\"$OLD_KEY\"" "$INSTALLED_PLUGINS" 2>/dev/null; then
  if command -v node &>/dev/null; then
    OLD_KEY_VAL="$OLD_KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" node -e '
      const fs = require("fs");
      const path = process.env.PLUGINS_FILE;
      const key = process.env.OLD_KEY_VAL;
      const s = JSON.parse(fs.readFileSync(path, "utf8"));
      if (s.plugins) delete s.plugins[key];
      fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
    ' 2>/dev/null || true
  fi
fi

# --- Register in installed_plugins.json ---------------------------------------

if [ ! -f "$INSTALLED_PLUGINS" ]; then
  echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS"
fi

if command -v node &>/dev/null; then
  PLUGIN_DIR_VAL="$PLUGIN_DIR" PLUGIN_KEY_VAL="$PLUGIN_KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" PLUGIN_VER="$PLUGIN_VERSION" \
  node -e '
    const fs = require("fs");
    const path = process.env.PLUGINS_FILE;
    const key = process.env.PLUGIN_KEY_VAL;
    const dir = process.env.PLUGIN_DIR_VAL;
    const ver = process.env.PLUGIN_VER;
    const s = JSON.parse(fs.readFileSync(path, "utf8"));
    if (!s.plugins) s.plugins = {};
    const now = new Date().toISOString();
    if (!s.plugins[key] || !Array.isArray(s.plugins[key]) || s.plugins[key].length === 0) {
      s.plugins[key] = [{ scope: "user", installPath: dir, version: ver, installedAt: now, lastUpdated: now }];
      console.log("[claude-subteams] Registered in installed_plugins.json.");
    } else {
      s.plugins[key][0].lastUpdated = now;
      s.plugins[key][0].version = ver;
      console.log("[claude-subteams] Already registered — updated timestamp and version.");
    }
    fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
  '
elif command -v python3 &>/dev/null; then
  PLUGIN_DIR_VAL="$PLUGIN_DIR" PLUGIN_KEY_VAL="$PLUGIN_KEY" PLUGINS_FILE="$INSTALLED_PLUGINS" PLUGIN_VER="$PLUGIN_VERSION" \
  python3 -c '
import json, os
from datetime import datetime, timezone
path = os.environ["PLUGINS_FILE"]
key = os.environ["PLUGIN_KEY_VAL"]
d = os.environ["PLUGIN_DIR_VAL"]
ver = os.environ["PLUGIN_VER"]
with open(path) as f:
    s = json.load(f)
s.setdefault("plugins", {})
now = datetime.now(timezone.utc).isoformat()
if key not in s["plugins"] or not isinstance(s["plugins"][key], list) or len(s["plugins"][key]) == 0:
    s["plugins"][key] = [{"scope": "user", "installPath": d, "version": ver, "installedAt": now, "lastUpdated": now}]
    print("[claude-subteams] Registered in installed_plugins.json.")
else:
    s["plugins"][key][0]["lastUpdated"] = now
    s["plugins"][key][0]["version"] = ver
    print("[claude-subteams] Already registered — updated timestamp and version.")
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
'
else
  echo "[claude-subteams] WARNING: Neither node nor python3 found."
  echo "  See INSTALL.md for manual registration steps."
fi

# --- Add to settings.json enabledPlugins --------------------------------------

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

if ! grep -qF "\"$PLUGIN_KEY\"" "$SETTINGS" 2>/dev/null; then
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

# --- Warn about superpowers conflict ------------------------------------------

if grep -q '"superpowers@claude-plugins-official": true' "$SETTINGS" 2>/dev/null; then
  echo ""
  echo "[claude-subteams] WARNING: The 'superpowers' plugin is enabled."
  echo "  claude-subteams replaces superpowers methodology."
  echo "  Running both may cause conflicts."
  if [ -t 0 ]; then
    read -r -p "  Disable superpowers now? [y/N] " ANSWER
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

# --- Verify -------------------------------------------------------------------

echo ""
SKILL_COUNT=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$PLUGIN_DIR/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
HOOK_COUNT=$(find "$PLUGIN_DIR/hooks" -maxdepth 1 -type f -not -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
echo "[claude-subteams] Installed (v$PLUGIN_VERSION):"
echo "  Skills : $SKILL_COUNT"
echo "  Agents : $AGENT_COUNT"
echo "  Hooks  : $HOOK_COUNT"
echo "  Key    : $PLUGIN_KEY"
echo "  Path   : $PLUGIN_DIR"

if [ "$SKILL_COUNT" -lt 10 ]; then
  echo ""
  echo "[claude-subteams] WARNING: Only $SKILL_COUNT skills found — something went wrong."
  echo "  See INSTALL.md for troubleshooting."
fi

# --- CLAUDE.md snippet (interactive only) -------------------------------------

if [ -t 0 ]; then
  echo ""
  if [ -f "CLAUDE.md" ] && grep -q "claude-subteams" "CLAUDE.md" 2>/dev/null; then
    echo "[claude-subteams] Activation snippet already in ./CLAUDE.md — skipping."
  elif [ -f "CLAUDE.md" ]; then
    read -r -p "[claude-subteams] Add activation snippet to ./CLAUDE.md? [y/N] " ADD_SNIPPET
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
  else
    echo "[claude-subteams] No CLAUDE.md in current directory — snippet not added."
    echo "  Add it manually later. See README.md for the snippet."
  fi
fi

echo ""
echo "[claude-subteams] Done. Restart Claude Code (/reload-plugins or new session)."
