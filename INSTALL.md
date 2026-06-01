# Manual Installation Guide

This document covers manual / fallback installation when the primary marketplace path is unavailable.

## Upgrading from a pre-marketplace install (v1.7 and earlier)

If you previously installed via the old `install.sh` script (pre-Phase 6), a stale local marketplace clone lives at `~/.claude/plugins/marketplaces/bn-skn/`. Remove it before reinstalling:

```bash
# Remove old marketplace registration (if it was written to known_marketplaces.json)
claude plugin marketplace remove bn-skn 2>/dev/null || true
# Remove the old directory
rm -rf "$HOME/.claude/plugins/marketplaces/bn-skn"
```

Then follow the primary path below.

## Primary path (recommended)

Inside Claude Code, run:

```
/plugin marketplace add bn-skn/claude-subteams
/plugin install claude-subteams@articortex
```

Or with the `claude` CLI:

```bash
claude plugin marketplace add bn-skn/claude-subteams
claude plugin install claude-subteams@articortex
```

**Private repo auth required.** Configure git credentials before running:

```bash
gh auth login
gh auth setup-git
```

Or set `GITHUB_TOKEN` in your environment for non-interactive / CI use.

After install, reload Claude Code (`/reload-plugins` or new session).

---

## Fallback: manual clone

If the marketplace CLI is unavailable or fails, clone and let Claude Code discover the plugin:

### Step 1: Clone the repo

Clone into a temporary location, then let the CLI install from there:

```bash
git clone https://github.com/bn-skn/claude-subteams /tmp/claude-subteams
```

### Step 2: Register via CLI

```bash
claude plugin marketplace add bn-skn/claude-subteams
claude plugin install claude-subteams@articortex
```

The CLI manages the final install location. Do not manually place files in `~/.claude/plugins/marketplaces/` — the layout depends on the `source` field in `marketplace.json` and may not match a hand-crafted path.

### Step 3: Activate in your project

Add this to your project's `CLAUDE.md`:

```markdown
## Development Methodology

For development tasks use the claude-subteams plugin (orchestrator + specialized sub-team agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent, gpt-code-reviewer, gpt-devils-advocate.
```

### Step 4: Verify

Restart Claude Code (new session or `/reload-plugins`), then check:

- `/skills` should list `claude-subteams:using-subteams` and other skills
- `/agents` should list `claude-subteams:code-reviewer` and other agents

---

## Troubleshooting

**Skills not showing up?**
- Confirm reload: skills are only visible after `/reload-plugins` or a new session.
- Check that skills are flat: `skills/{name}/SKILL.md`, NOT `skills/category/{name}/SKILL.md`
- Claude Code only scans one level deep under `skills/`

**Marketplace add fails with auth error?**
- Run `gh auth status` to confirm GitHub credentials.
- Run `gh auth login && gh auth setup-git` if not configured.
- Alternatively set `GITHUB_TOKEN` in your environment.

**`claude plugin` subcommand not recognized?**
- Run `claude plugin --help` to see available subcommands.
- The CLI version may differ from what this guide expects — adjust accordingly.

**Conflicts with superpowers?**
- Remove `"superpowers@claude-plugins-official": true` from `~/.claude/settings.json` enabledPlugins.
