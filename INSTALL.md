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

## Requirements

- **Claude Code ≥ 2.1.284** — the plugin's `bin/` commands (`subteams-tests`, `subteams-browser`) and the test receipts depend on it.
- **git** — marketplace cloning.
- **jq** — used by the hooks; mandatory in a project with a test contract (without it the commit gate blocks every commit there).
- **Node.js / npm** — the TypeScript check in `pre-commit-gate` and the one-time agent-browser install.
- **Chrome** (system install), or run `subteams-browser setup` once — for the live UI review.

Details: README "Requirements" and "Project suites & UI verification".

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

Copy the content of `templates/claudemd-snippet.md` (in the cloned repo, or in the installed plugin: `find "$HOME/.claude/plugins" -name "claudemd-snippet.md" 2>/dev/null`) into your project's `CLAUDE.md`. That file is the current snippet; README "Activation" shows an excerpt.

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

**Marketplace add fails?**
- Confirm network access to `github.com`.
- Confirm your `claude` CLI supports the subcommand: `claude plugin marketplace --help`.

**`claude plugin` subcommand not recognized?**
- Run `claude plugin --help` to see available subcommands.
- The CLI version may differ from what this guide expects — adjust accordingly.

**Conflicts with superpowers?**
- Remove `"superpowers@claude-plugins-official": true` from `~/.claude/settings.json` enabledPlugins.
