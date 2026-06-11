# claude-subteams — Cheat Sheet

Quick reference for installing, updating, removing, and **repairing** the plugin from any machine.

- **Repo:** `bn-skn/claude-subteams` (private)
- **Marketplace:** `articortex` · **Plugin:** `claude-subteams` · **Version:** 1.17.1
- **Contents:** 16 agents, 53 skills, 6 hooks

---

## Install

Prerequisite (private repo): authenticate GitHub on the machine first.

```bash
gh auth login && gh auth setup-git      # or: export GITHUB_TOKEN=ghp_...
```

Then, inside Claude Code:

```
/plugin marketplace add bn-skn/claude-subteams
/plugin install claude-subteams@articortex
/reload-plugins                          # activate (or start a new session)
```

CLI equivalent:

```bash
claude plugin marketplace add bn-skn/claude-subteams
claude plugin install claude-subteams@articortex
```

Via an AI agent: hand it `llms-install.md` → `@llms-install.md install this plugin`.

Activate in a project: add the snippet from `templates/claudemd-snippet.md` to the project's `CLAUDE.md`.

---

## Update

```bash
claude plugin marketplace update articortex        # 1. refresh catalog (pull latest main)
claude plugin update claude-subteams@articortex    # 2. upgrade the installed plugin
```
Then `/reload-plugins` (or a new session) to apply. Step 1 pulls the latest `main` from the private repo into the marketplace catalog; step 2 bumps the **installed** plugin to that version. `marketplace update` alone is not enough — the installed plugin is version-pinned and only `plugin update` moves it.

Interactive equivalent: `/plugin marketplace update articortex` → `/plugin update claude-subteams@articortex` → `/reload-plugins`.

---

## Uninstall

```bash
claude plugin uninstall claude-subteams@articortex
claude plugin marketplace remove articortex      # optional: also drop the marketplace
```
Via an AI agent: `@llms-uninstall.md`.

---

## Repair — broken `/plugins` or legacy "костыль" install

The pre-v1.14 `install.sh` hand-edited Claude Code's global JSON and registered a fake
`source: "local"` marketplace named `bn-skn`. After a Claude Code update that source type
became invalid and **corrupts the marketplace list — `/plugins` won't open at all.**

### Case A — `/plugins` (and `claude plugin marketplace list`) still works

```bash
claude plugin marketplace remove bn-skn           # drop the stale local registration
rm -rf ~/.claude/plugins/marketplaces/bn-skn      # delete the old clone
# reinstall cleanly:
claude plugin marketplace add bn-skn/claude-subteams
claude plugin install claude-subteams@articortex
```

### Case B — `/plugins` is dead ("Marketplace configuration file is corrupted")

The CLI may choke on the bad entry, so edit the state files directly (back up first):

```bash
cd ~/.claude/plugins
cp known_marketplaces.json{,.bak}
cp installed_plugins.json{,.bak}
cp ~/.claude/settings.json ~/.claude/settings.json.bak

# remove the broken bn-skn entry from all three:
jq 'del(.["bn-skn"])' known_marketplaces.json > t && mv t known_marketplaces.json
jq 'del(.plugins["claude-subteams@bn-skn"])' installed_plugins.json > t && mv t installed_plugins.json
jq 'if .enabledPlugins then .enabledPlugins |= del(.["claude-subteams@bn-skn"]) else . end' \
   ~/.claude/settings.json > t && mv t ~/.claude/settings.json

rm -rf ~/.claude/plugins/marketplaces/bn-skn
```

`/plugins` revives immediately. Then reinstall via the marketplace flow above
(after `gh auth login && gh auth setup-git`).

> Safety: never blanket-`rm` `~/.claude/plugins/` — that wipes ALL your plugins.
> Touch only the `bn-skn` / `claude-subteams@bn-skn` entries. Back up before editing.

---

## Plugin commands (in a session)

| Command | What it does |
|---|---|
| `/research <question>` | Fetch current docs (Context7 + web) before coding |
| `/whatsnew <lib> [N months]` | Changelog / breaking changes for a library |
| `/cross-review` | Review with 4 critics (2 Claude + 2 GPT) |
| `/rescue` | Codex diagnoses a stuck bug |
| `/init-project <name>` | Bootstrap a new project skeleton (project-scaffold skill) |

The `using-subteams` skill auto-loads at the start of any development work.

---

## Cross-review setup (GPT via Codex)

Needs the Codex CLI on a machine **without a Russia IP block** (`codex login` — ChatGPT Plus).

- **Model:** default = whatever `~/.codex/config.toml` is set to. Change it there and the
  critics inherit it natively — no plugin edit.
- **Override:** `export CROSS_REVIEW_MODEL=<model>` and/or `export CROSS_REVIEW_EFFORT=high`
  (effort defaults to `high` — never the shallow Codex default).
- If Codex is unavailable, cross-review gracefully skips; the Claude critics still run.
- `openai/codex-plugin-cc` (OpenAI's own plugin) can be installed separately for interactive
  `/codex:review` — it is independent of this plugin's cross-review.

---

## Diagnostics

```bash
claude plugin list                  # what's installed + status
claude plugin marketplace list      # configured marketplaces
claude plugin validate .            # validate the manifest (run in the repo)
ls ~/.claude/plugins/*.json         # global state (BACK UP before editing)
```

---

## Notes

- The repo is **private** — do not submit to the public `claude-community` marketplace
  unless you intend to make it public. Self-hosting from the private repo is fully supported.
- Marketplace name `articortex` is deliberately **different** from the plugin name
  `claude-subteams` to avoid the cache-recursion bug (marketplace-name == plugin-name).
- Dev copy of the repo lives at `~/claude-subteams` on the main machine.
