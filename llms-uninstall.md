# claude-subteams — LLM Uninstallation Protocol

You are removing the **claude-subteams** plugin from Claude Code on the user's machine via the official plugin CLI. Follow every step. Stop with a clear report if a gate fails.

---

## 1. Confirm the plugin is installed

```bash
claude plugin list 2>/dev/null | grep -F "claude-subteams" && echo "INSTALLED" || echo "NOT INSTALLED"
```

**Pass:** output contains `INSTALLED`.
**If NOT INSTALLED:** the plugin may already be removed or was never installed. Check the plugin directory for partial state before stopping.

```bash
find "$HOME/.claude/plugins" -name "plugin.json" 2>/dev/null | grep "claude-subteams" && echo "DIR EXISTS" || echo "DIR ABSENT"
```

If both checks return "not installed" / "absent", there is nothing to remove. Report that to the user and stop.

---

## 2. Uninstall the plugin

```bash
claude plugin uninstall claude-subteams@articortex
```

**Pass:** exits 0 and confirms the plugin was removed.
**Fail:** non-zero exit. Capture the full stderr and report it to the user. Run `claude plugin --help` to verify the exact subcommand if needed.

---

## 3. Remove the marketplace entry (optional)

If the user wants to fully deregister the `articortex` marketplace (not just remove this plugin):

```bash
claude plugin marketplace remove articortex
```

This is optional. Leaving the marketplace registered has no side effects unless another plugin from it is installed later.

---

## 4. Verify removal

### 4a. Plugin no longer listed

```bash
claude plugin list 2>/dev/null | grep -F "claude-subteams" && echo "STILL PRESENT" || echo "REMOVED"
```

**Pass:** `REMOVED`.

### 4b. Plugin directory gone

```bash
find "$HOME/.claude/plugins" -name "plugin.json" 2>/dev/null | grep "claude-subteams" && echo "STILL PRESENT" || echo "REMOVED"
```

**Pass:** `REMOVED`.

If any check shows `STILL PRESENT`, the CLI uninstall did not complete cleanly. Remove the marketplace clone root manually (this is safe — `articortex` currently has one plugin and `marketplace remove` is idempotent):

```bash
claude plugin marketplace remove articortex 2>/dev/null || true
rm -rf "$HOME/.claude/plugins/marketplaces/articortex"
```

Then re-run the checks.

---

## 5. Report to user

**Removed:** `claude-subteams@articortex` from the plugin registry. Plugin directory deleted.

**Requires manual action:**

1. **Remove the CLAUDE.md snippet.** If you added the activation block to your project's `CLAUDE.md` or `~/.claude/CLAUDE.md`, delete the `## Development Methodology` section added by this plugin.

2. **Reload Claude Code.** Run `/reload-plugins` or start a new session for the removal to take effect.

3. **Re-enable superpowers** (optional). If superpowers was disabled during install and you want it back, add `"superpowers@claude-plugins-official": true` to the `enabledPlugins` block in `~/.claude/settings.json`.

**Not removed:** any project-level files you created using plugin templates (`CONVENTIONS.md`, `ARCHITECTURE.md`, `BACKLOG.md`, `CHANGELOG.md`, ADR files). Those belong to your project and are yours to keep or delete.
