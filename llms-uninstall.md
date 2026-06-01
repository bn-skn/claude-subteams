# claude-subteams — LLM Uninstallation Protocol

You are removing the **claude-subteams** plugin from Claude Code on the user's machine. Follow every step. Stop with a clear report if a gate fails.

---

## 1. Confirm the plugin is installed

```bash
grep -F '"claude-subteams@bn-skn"' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null && echo "INSTALLED" || echo "NOT INSTALLED"
```

**Pass:** output is `INSTALLED`.
**If NOT INSTALLED:** the plugin may already be removed or was never installed. Check `settings.json` and the plugin directory for partial state before stopping.

```bash
ls "$HOME/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams" 2>/dev/null && echo "DIR EXISTS" || echo "DIR ABSENT"
```

If both checks return "not installed" / "absent", there is nothing to remove. Report that to the user and stop.

---

## 2. Run the uninstall script

```bash
bash "$HOME/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams/scripts/uninstall.sh"
```

The script runs non-interactively (removes the plugin directory without prompting) when stdin is not a terminal.

**Pass:** script exits 0 and prints `[claude-subteams] Uninstall complete.`
**Fail:** non-zero exit. Report the full stderr to the user. Proceed to step 3 to check partial state.

---

## 3. Verify removal

### 3a. installed_plugins.json — key gone

```bash
grep -F '"claude-subteams@bn-skn"' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null && echo "STILL PRESENT" || echo "REMOVED"
```

**Pass:** `REMOVED`.

### 3b. settings.json — key gone

```bash
grep -F '"claude-subteams@bn-skn"' "$HOME/.claude/settings.json" 2>/dev/null && echo "STILL PRESENT" || echo "REMOVED"
```

**Pass:** `REMOVED`.

### 3c. known_marketplaces.json — entry gone

```bash
grep -F '"bn-skn"' "$HOME/.claude/plugins/known_marketplaces.json" 2>/dev/null && echo "STILL PRESENT" || echo "REMOVED"
```

**Pass:** `REMOVED`.

### 3d. Plugin directory removed

```bash
ls "$HOME/.claude/plugins/marketplaces/bn-skn" 2>/dev/null && echo "DIR EXISTS" || echo "DIR REMOVED"
```

**Pass:** `DIR REMOVED`.

If any check shows `STILL PRESENT` or `DIR EXISTS`, the uninstall script did not complete cleanly. Remove the remaining entries manually (delete the JSON keys with any text editor and `rm -rf` the directory), then re-run the checks.

---

## 4. Report to user

**Removed:** `claude-subteams@bn-skn` from `installed_plugins.json`, `settings.json`, and `known_marketplaces.json`. Plugin directory deleted.

**Requires manual action:**

1. **Remove the CLAUDE.md snippet.** If you added the activation block to your project's `CLAUDE.md` or `~/.claude/CLAUDE.md`, delete the `## Development Methodology` section added by this plugin.

2. **Reload Claude Code.** Run `/reload-plugins` or start a new session for the removal to take effect.

3. **Re-enable superpowers** (optional). If superpowers was disabled during install and you want it back, add `"superpowers@claude-plugins-official": true` to the `enabledPlugins` block in `~/.claude/settings.json`.

**Not removed:** any project-level files you created using plugin templates (`CONVENTIONS.md`, `ARCHITECTURE.md`, `BACKLOG.md`, `CHANGELOG.md`, ADR files). Those belong to your project and are yours to keep or delete.
