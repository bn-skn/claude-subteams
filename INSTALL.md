# Manual Installation Guide

If the install script doesn't work, follow these steps manually.

## Step 1: Clone the repo

```bash
git clone https://github.com/bn-skn/claude-subteams ~/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams
```

## Step 2: Register the plugin

Add to `~/.claude/plugins/installed_plugins.json` (create if missing):

```json
{
  "version": 2,
  "plugins": {
    "claude-subteams@bn-skn": [
      {
        "scope": "user",
        "installPath": "/YOUR/HOME/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams",
        "version": "1.1.0",
        "installedAt": "2026-01-01T00:00:00.000Z",
        "lastUpdated": "2026-01-01T00:00:00.000Z"
      }
    ]
  }
}
```

Replace `/YOUR/HOME` with your actual home directory path.

## Step 3: Enable the plugin

Add to `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "claude-subteams@bn-skn": true
  }
}
```

If the file already exists, merge `enabledPlugins` into the existing object.

## Step 4: Activate in your project

Add this to your project's `CLAUDE.md`:

```markdown
## Development Methodology

For development tasks use the claude-subteams plugin (orchestrator + 9 specialized agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate.
```

## Step 5: Verify

Restart Claude Code (new session or `/reload-plugins`), then check:
- `/skills` should list `claude-subteams:using-subteams` and ~45 other skills
- `/agents` should list `claude-subteams:code-reviewer` and 8 other agents

## Troubleshooting

**Skills not showing up?**
- Check that skills are flat: `skills/{name}/SKILL.md`, NOT `skills/category/{name}/SKILL.md`
- Claude Code only scans one level deep under `skills/`

**Plugin not recognized?**
- Check `installed_plugins.json` — `installPath` must be absolute and correct
- Check `settings.json` — `enabledPlugins` key must match exactly: `"claude-subteams@bn-skn": true`

**Conflicts with superpowers?**
- Remove `"superpowers@claude-plugins-official": true` from `settings.json` enabledPlugins
