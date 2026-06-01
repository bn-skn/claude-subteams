# claude-subteams

A Claude Code plugin that replaces ad-hoc prompting with a structured team methodology: one orchestrator Claude leads specialized sub-teams (code reviewer, test engineer, architecture guard, security auditor, and others), each dispatched with a precise brief, reviewed output, and integrated result — producing code that survives production.

## Philosophy

You are the **orchestrator**. You understand the work deeply, set direction, delegate parallelizable or specialized tasks to sub-team agents, verify every result yourself, and never hide behind subagents. Sub-teams are smart agents, not dumb executors — brief them with full context and they return structured, verifiable output.

## Quick Install

Inside Claude Code, run these two commands:

```
/plugin marketplace add bn-skn/claude-subteams
/plugin install claude-subteams@articortex
```

Or with the `claude` CLI:

```bash
claude plugin marketplace add bn-skn/claude-subteams
claude plugin install claude-subteams@articortex
```

**Private repo auth required.** This repo is private. Before running either path, ensure your GitHub credentials are configured:

```bash
gh auth login
gh auth setup-git
```

Or set `GITHUB_TOKEN` in your environment for non-interactive / CI use.

A convenience shell wrapper is also available:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bn-skn/claude-subteams/main/scripts/install.sh)
```

If the script doesn't work, see [INSTALL.md](INSTALL.md) for manual steps.

For install / update / uninstall / **repair** commands in one place, see [docs/CHEATSHEET.md](docs/CHEATSHEET.md) — including how to fix a broken `/plugins` or a legacy script-based install.

### Install via an AI agent

You can hand `llms-install.md` to any coding agent (Cursor, Windsurf, Claude Code itself, etc.) and it will run the pre-flight checks, execute the marketplace install, and verify the result — no manual steps required. Example invocation:

```
@llms-install.md install this plugin
```

The protocol walks the agent through dependency checks, auth verification, marketplace add/install, reload instructions, and the post-reload smoke test. A companion `llms-uninstall.md` covers the reverse path.

### Development / Testing

To test the plugin locally without installing:

```bash
git clone https://github.com/bn-skn/claude-subteams /path/to/claude-subteams
claude --plugin-dir /path/to/claude-subteams
```

Use `/reload-plugins` inside Claude Code to hot-reload after changes.

### Requirements

- **git** — required for marketplace cloning (private repo)
- **gh** (GitHub CLI) — needed for private repo auth (`gh auth login && gh auth setup-git`)
- **Node.js** (via nvm or global) — required for pre-commit-gate hook (tsc check)
- **jq** — used by hooks to parse JSON input

### Update

```bash
claude plugin marketplace update articortex
```

Or with the shell wrapper:

```bash
bash scripts/update.sh
```

### Uninstall

```bash
claude plugin uninstall claude-subteams@articortex
```

Or with the shell wrapper:

```bash
bash scripts/uninstall.sh
```

### Upgrading from a pre-marketplace install (v1.7 and earlier)

If you installed via the old `install.sh` script, remove the stale local marketplace before reinstalling:

```bash
claude plugin marketplace remove bn-skn 2>/dev/null || true
rm -rf "$HOME/.claude/plugins/marketplaces/bn-skn"
```

Then follow the Quick Install steps above.

## Activation

After install, add this snippet to your project's `CLAUDE.md` (or global `~/.claude/CLAUDE.md`):

```markdown
## Development Methodology

For development tasks use the claude-subteams plugin (orchestrator + specialized sub-team agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent, gpt-code-reviewer, gpt-devils-advocate.
```

This is also available as a file: `templates/claudemd-snippet.md`.

**To deactivate:** remove the snippet from CLAUDE.md. No need to uninstall the plugin.

## Skills

| Sub-team | Skill | Description |
|---|---|---|
| core | `using-subteams` | Orchestrator meta-skill — methodology, pipeline, red flags. Loaded at session start. |
| core | `orchestrator-briefing` | Subagent communication protocol. Use before every Agent tool call. |
| core | `model-selection` | Guide for choosing sonnet vs opus per task type. |
| architecture | `clean-architecture` | Enforces layered architecture, dependency direction, and file size limits. |
| architecture | `conventions-enforcer` | Validates project structure against CONVENTIONS.md. |
| scaffolding | `project-scaffold` | Run-once wizard that bootstraps a brand-new project's doc/config skeleton (CLAUDE.md, SYSTEM.md, docs tree, .gitignore). Complements the component-level `scaffolding` skill. |
| design | `design-to-code` | Pipeline from text spec to working code with browser preview and feedback loop. |
| design | `design-qa` | Compares implementation against design spec; heuristic evaluation and visual consistency. |
| ops | `ci-cd-pipeline` | Sets up and modifies CI/CD pipelines and environment promotion strategies. |
| process | `brainstorming` | Explores intent and requirements before any implementation. Use before creative work. |
| process | `decision-context` | Mandatory block (Decision / Why / Alternatives / Risks / Linked) in the decisions journal for every non-trivial commit. Everyday companion to `adr-tracker`. |
| process | `doc-quality-gate` | Classifies a change (cosmetic/feature/architectural/breaking) and defines the docs each class needs. Pairs with the session-end-reminder hook's breaking-signal escalation. |
| quality | `code-review` | Structured review checklist: security, correctness, performance, SOLID principles. |
| quality | `adversarial-testing` | Writes tests designed to break the code — edge cases, race conditions, boundary violations. |
| quality | `ui-testing` | Browser-based UI testing with Playwright CLI. Visual regression, interaction testing, CI-ready E2E. |
| quality | `codebase-improvement` | Proactive codebase analysis. Dispatches improvement-agent for health checks and tech debt discovery. |
| research | `live-research` | Fetches current library/API docs before coding against fast-moving SDKs (`/research`, `/whatsnew`). Orchestrator fetches via Context7/web; researcher synthesizes. |
| cross-model | `cross-review` | Runs Codex/GPT critics alongside Claude critics to break model-monoculture blind spots (`/cross-review`, `/rescue`). Full set by default (2 Claude + 2 GPT); Claude-only when Codex is down. Strongest model at high reasoning effort, native default. |

## Agents

| Agent | Model | Role |
|---|---|---|
| `code-reviewer` | opus | Senior code review: security, correctness, performance, SOLID. Read-only access. |
| `test-engineer` | opus | Adversarial test writing and test suite maintenance. Full file access. |
| `architecture-guard` | opus | Structural and dependency drift checks. Read-only access. |
| `design-critic` | opus | UI implementation vs. design spec compliance. Read-only access. |
| `prompt-evaluator` | opus | Prompt and skill regression testing. Read + write. |
| `doc-agent` | sonnet | Documentation freshness checks and updates. Write access, no Bash. |
| `researcher` | opus | Deep technology research. Read + web (WebSearch, WebFetch). |
| `security-auditor` | opus | Security-sensitive changes, secrets, and auth flows. Read-only access. |
| `devils-advocate` | opus | Challenges assumptions: "what if?", edge cases, scale, necessity. Full pipeline only. |
| `developer` | sonnet | Implementation specialist: modular code, minimal diffs, style preservation. |
| `ui-tester` | sonnet | Browser-based UI/E2E testing via Playwright CLI. Screenshots, interactions, visual regression. |
| `improvement-agent` | opus | Proactive codebase analyst. Finds improvement opportunities, returns prioritized proposals (read-only). |
| `gpt-code-reviewer` | sonnet (+Codex/GPT-5.5) | Cross-model code review via `codex exec`. Finds bug classes Claude-family models under-weight. Read-only; graceful-skips if Codex unavailable. |
| `gpt-devils-advocate` | sonnet (+Codex/GPT-5.5) | Cross-model architectural challenge via `codex exec`. Different training distribution than Claude. Read-only; graceful-skip. |

## Hooks

| Event | Hook | Purpose |
|---|---|---|
| `SessionStart` | `session-start` | Checks for stale BACKLOG items and active plans from previous sessions. No prompt injection — activation via CLAUDE.md. |
| `PreToolUse` (Bash) | `pre-commit-gate` | Runs tsc / mypy / go build before any git commit; warns on files over 200 lines. |
| `PreToolUse` (Bash) | `pre-push-check` | Safety check before git push. |
| `PostToolUse` (Edit/Write) | `post-edit-check` | Async check after file edits. |
| `Stop` | `session-end-reminder` | **Enforces** documentation discipline at end of work. Detects unstaged code changes; if any non-doc files changed without `*.md` updates, blocks Stop with instructions to update the decisions journal. Escalates to the full breaking-change checklist when it detects asymmetric signals (file deletions, schema/migration files) — see the `doc-quality-gate` skill. Counter resets on each new commit; after 2 enforcement attempts per HEAD, allows stop with audit warning. Escape hatch: `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1`. See "Configuration" below. |
| `UserPromptSubmit` | `user-prompt-check` | Async prompt validation. |

## Configuration

### Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK` | Set to `1` to disable the Stop hook's documentation enforcement. Use for scratch / experimental work where doc updates are deliberately deferred, or in CI / batch contexts where the cycle does not apply. | unset (enforcement active) |

### Doc-enforcement details

The `session-end-reminder` hook enforces the doc cycle described in the `decision-context` skill. Logic:

- **No changes in working tree** → silent pass.
- **Only `*.md` files changed** → silent pass (docs are what changed).
- **Code + docs both changed** → soft reminder to confirm the Decision-context block is in the journal.
- **Code changed without any `*.md` updates** → block Stop (`exit 2`) with instructions. After 2 attempts in the same HEAD state, allows stop with audit warning. Counter resets on each new commit.
- **Not in a git repo** → soft checklist only, no enforcement.
- **`CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1`** → all enforcement bypassed.

Neutral files that never trigger enforcement: `.gitignore`, `.gitattributes`, `.editorconfig`, lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `go.sum`, `poetry.lock`, `uv.lock`, `composer.lock`), `.DS_Store`.

## Templates

Project scaffolding templates in `templates/`:

| File | Purpose |
|---|---|
| `CONVENTIONS.md` | Coding conventions: structure, naming, limits, error handling. |
| `ARCHITECTURE.md` | Architecture documentation: diagram, layers, data flow, ADR links. |
| `BACKLOG.md` | Task tracking: in progress, next up, ideas, done. |
| `CHANGELOG.md` | Keep-a-Changelog format for release notes. |
| `adr-template.md` | Lightweight MADR for architectural decisions. |

Bootstrap templates for new projects in `templates/project-init/` (used by the `project-scaffold` skill):

| File | Purpose |
|---|---|
| `SYSTEM.md` | Two-layer template: system description + append-only decisions journal (decision-context format). |
| `CLAUDE.md` | Full project instructions template wired into this plugin's methodology. |
| `README.md` | Minimal project README with stack/setup/usage placeholders. |
| `dot-gitignore` | Stack-agnostic .gitignore (renamed to `.gitignore` at scaffold time). |

## vs. superpowers

| | claude-subteams | superpowers |
|---|---|---|
| Focus | Team methodology + full SDLC pipeline | Broad collection of individual skills |
| Orchestration | First-class: briefing protocol, file conflict prevention | Per-skill dispatch |
| Hooks | Pre-commit gate, session start/end, post-edit | Varies |
| Agent roster | Built-in named agents with defined roles | Ad-hoc |
| Compatibility | Use one or the other — not both | Use one or the other — not both |

## License

MIT
