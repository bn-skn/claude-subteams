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

Two canonical steps — refresh the marketplace catalog, then update the installed plugin:

```bash
claude plugin marketplace update articortex        # 1. pull latest main from the repo into the catalog
claude plugin update claude-subteams@articortex    # 2. bump the installed plugin to that version
```

Then restart Claude Code (or `/reload-plugins`) to apply. `marketplace update` alone refreshes the source but does NOT change the installed (version-pinned) plugin — step 2 is what actually upgrades it.

Interactive equivalent inside Claude Code:

```
/plugin marketplace update articortex
/plugin update claude-subteams@articortex
/reload-plugins
```

Or with the shell wrapper (does both steps):

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
For small fixes — act directly, invoke code-review after if logic changed. Any logic change gets code-reviewer (and devils-advocate for non-trivial logic) — no "it's just one line" exemption.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent, gpt-code-reviewer, gpt-devils-advocate, prompt-engineer, agent-architect.
Building/editing agents, prompts, skills, or multi-agent systems → invoke agent-architect + prompt-engineer + prompt-evaluator (using-subteams Section 6.5).
```

This is also available as a file: `templates/claudemd-snippet.md`.

**To deactivate:** remove the snippet from CLAUDE.md. No need to uninstall the plugin.

## Skills

All 55 skills (auto-loaded on demand by description match; `using-subteams` loads at session start):

| Sub-team | Skill | Description |
|---|---|---|
| core | `using-subteams` | Orchestrator meta-skill — methodology, pipeline, red flags. Loaded at session start. |
| core | `orchestrator-briefing` | Subagent communication protocol. Use before every Agent tool call. Now includes a mandatory `Rails:` briefing field (conventions/architecture docs + active plan) and a `Rails read:` output-contract line. |
| core | `model-selection` | Guide for choosing sonnet vs opus per task type. |
| core | `context-management` | Managing the context window, checkpoints, and session summaries. |
| agents | `agent-engineering` | Design multi-agent systems: orchestrator + specialists, context engineering, token efficiency, standardized contracts. |
| agents | `subagent-prompt-design` | Design subagent prompts: minimal context, restricted tools, standardized output, explicit handoff. |
| planning | `brainstorming` | Explores intent and requirements before any implementation. For greenfield/structural work, captures decisions as ADRs and projects them into `ARCHITECTURE.md`/`CONVENTIONS.md` (gated by `check-arch-docs.sh`). |
| planning | `writing-plans` | Turn a spec into a step-by-step implementation plan before touching code. |
| planning | `living-plan` | The single plan-of-record every actor reads/writes, in two weights — a light contract (scope / acceptance criteria / non-goals) for risk-triggered or multi-session work, or a full package → criterion → status matrix for multi-package/contracted work. Write-once acceptance criteria; validated by `check-plan.sh`. |
| execution | `executing-plans` | Execute a written plan with subagent orchestration and quality gates. Home of Autonomy Mode — bounded autonomous execution, opt-in per grant, gated by the `autonomy-gate` hook on a fresh contract record. Contains agent *drift* off scope; not a sandbox against a shell-equipped agent (see ADR-007). |
| execution | `subagent-driven-dev` | Fresh subagent per independent task with two-stage review. |
| execution | `parallel-dispatch` | Run 2+ independent tasks concurrently without shared state or sequential dependencies. |
| execution | `finishing-branch` | Decide how to integrate completed work — merge, PR, or cleanup. |
| execution | `receiving-review` | Verify and triage review feedback with technical rigor before implementing it. |
| execution | `verification-gate` | Evidence before "done": run verification commands, backups, doc/compile/visual checks. Authoritative home of the honesty invariant — claim provenance, tool-failure honesty. |
| execution | `systematic-debugging` | Reproduce → root-cause → fix → verify, before proposing any fix. |
| execution | `self-optimization` | Iterative improve-test-deploy cycle for prompts, skills, and CLAUDE.md. |
| docs | `decision-context` | Mandatory Decision / Why / Alternatives / Risks / Linked block for every non-trivial change. Companion to `adr-tracker`. |
| docs | `adr-tracker` | Numbered lightweight-MADR ADRs in `docs/adr/` for project-wide decision history. |
| docs | `doc-quality-gate` | Classifies a change (cosmetic/feature/architectural/breaking) and defines the docs each class needs. |
| docs | `claudemd-engineering` | Standards for writing and maintaining concise, prioritized, regularly-pruned CLAUDE.md files. |
| docs | `skill-engineering` | Standards for high-quality SKILL.md: one job per skill, numbered checklists, critical rules, mandatory testing. |
| architecture | `clean-architecture` | Enforces layered architecture, dependency direction, and file-size limits (requires CONVENTIONS.md). |
| architecture | `conventions-enforcer` | Validates project structure, file sizes, import direction, and naming against CONVENTIONS.md. |
| architecture | `service-boundaries` | Decision framework for service decomposition: split vs keep together, bounded contexts, data ownership. |
| architecture | `refactoring` | Safe refactoring: identifies god-files, circular deps, DRY violations; small steps with tests. |
| scaffolding | `project-scaffold` | Bootstrap a project doc/config skeleton — OR retrofit missing docs into an existing project (non-destructive). |
| scaffolding | `scaffolding` | Create new services, modules, API endpoints, skills, or agents from templates. |
| design | `design-to-code` | Pipeline from text spec to working code with design system, browser preview, and feedback loop. |
| design | `design-qa` | Compare implementation against spec: heuristic evaluation, visual consistency, responsiveness. |
| design | `accessibility` | WCAG 2.1 AA audit: semantic HTML, keyboard nav, screen readers, color contrast, ARIA. |
| quality | `code-review` | Structured review checklist: security, correctness, performance, SOLID — and how to brief the reviewer. |
| quality | `adversarial-testing` | Tests designed to break the code: edge cases, invalid data, race conditions, boundary violations. |
| quality | `test-driven-development` | Red-Green-Refactor: write the test first, watch it fail, write minimal code to pass. |
| quality | `ui-testing` | Browser UI testing via Playwright CLI: visual regression, interaction testing, CI-ready E2E. |
| quality | `codebase-improvement` | Proactive codebase analysis; dispatches improvement-agent for health checks and tech-debt discovery. |
| quality | `lint-and-style` | Consistent code style via linters, formatters, and editor config (ESLint, Prettier, EditorConfig). |
| quality | `prompt-evaluation` | Test prompts and skills against regression cases with pass/fail metrics. |
| security | `security-audit` | OWASP Top 10, prompt-injection, input validation, auth/authz; dispatches security-auditor. |
| security | `config-and-secrets` | Env config, secrets protection, .gitignore enforcement, rotation, protected-file integrity. |
| security | `dependency-audit` | Vulnerabilities, lockfile integrity, license compliance, unused packages, update strategy. |
| backend | `api-design` | REST design: resource naming, HTTP methods, status codes, versioning, Zod validation, OpenAPI. |
| backend | `database-design` | Schema design, migrations, query optimization; SQLite WAL mode and FTS5. |
| backend | `data-engineering` | Data pipelines, ETL processes, data validation, and data-quality systems. |
| backend | `error-handling` | Retry/backoff, circuit breakers, graceful degradation, structured errors; fix root causes. |
| ops | `ci-cd-pipeline` | Set up and modify CI/CD pipelines, deployment workflows, environment promotion. |
| ops | `git-workflow` | Branching strategy, conventional commits, and PR workflow. |
| ops | `using-git-worktrees` | Isolated git worktrees for feature work or plan execution. |
| ops | `monitoring-logging` | Structured logging, health checks, alerting, and observability for services. |
| ops | `incident-management` | Production incident response, root-cause analysis, and postmortems. |
| ops | `mobile-development` | Building, architecting, and deploying React Native, Flutter, or native apps. |
| ops | `i18n-localization` | Internationalization, translation workflows, and locale-specific formatting. |
| research | `live-research` | Fetch current library/API docs before coding against fast-moving SDKs (`/research`, `/whatsnew`). |
| cross-model | `cross-review` | GPT (Codex) + Claude critics in parallel to break model-monoculture blind spots (`/cross-review`, `/rescue`); Claude-only when Codex is down. |
| coordination | `multi-instance` | Opt-in coordination for several Claude Code instances on one repo: claim before edit, commit under a lock, mailbox + auto-notify. Portable (file-based, not agent-teams). `CLAUDE_SUBTEAMS_MULTI_INSTANCE=1`. |

## Agents

Every agent below carries a built-in honesty invariant right after "Who You Are" in its prompt — claim provenance (TRUSTED / ATTRIBUTED / UNVERIFIED), anti-hedge, tool-failure honesty, and a materiality threshold for when research is required. Authoritative detail lives in the `verification-gate` skill.

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
| `devils-advocate` | opus | Challenges assumptions: "what if?", edge cases, scale, necessity. Full pipeline + Standard (every logic change). |
| `developer` | sonnet | Implementation specialist: modular code, minimal diffs, style preservation. |
| `ui-tester` | sonnet | Browser-based UI/E2E testing via Playwright CLI. Screenshots, interactions, visual regression. |
| `improvement-agent` | opus | Proactive codebase analyst. Finds improvement opportunities, returns prioritized proposals (read-only). |
| `gpt-code-reviewer` | sonnet (+Codex/GPT-5.5) | Cross-model code review via `codex exec`. Finds bug classes Claude-family models under-weight. Read-only; graceful-skips if Codex unavailable. |
| `gpt-devils-advocate` | sonnet (+Codex/GPT-5.5) | Cross-model architectural challenge via `codex exec`. Different training distribution than Claude. Read-only; graceful-skip. |
| `prompt-engineer` | opus | Authors and optimizes prompts, system prompts, and tool/skill instructions. Context-first, eval-driven. Read + write. |
| `agent-architect` | opus | Designs subagents and multi-agent systems: boundaries, orchestration, tool scoping, contracts. Read + write. |

## Hooks

| Event | Hook | Purpose |
|---|---|---|
| `SessionStart` | `session-start` | Checks for stale BACKLOG items and active plans from previous sessions. No prompt injection — activation via CLAUDE.md. |
| `PreToolUse` (Bash) | `pre-commit-gate` | Runs tsc / mypy / go build before any git commit; warns on files over 200 lines. |
| `PreToolUse` (Bash) | `pre-push-check` | Safety check before git push. |
| `PreToolUse` (Edit/Write/MultiEdit/NotebookEdit/Bash) | `autonomy-gate` | Enforces scoped autonomy grants — blocks out-of-scope or cap-exceeding writes and edits to the grant's own run record before they land. Inert unless `CLAUDE_SUBTEAMS_AUTONOMY` is set. Delegates scope/cap checks to `scripts/autonomy-check.sh`. Contains agent drift off scope; not a sandbox against a shell-equipped agent — see [ADR-007](docs/adr/007-autonomy-enforcement-architecture.md). |
| `SubagentStart` | `subagent-rails` | Injects a static rails pointer + honesty reminder into every spawned subagent. Plugin text only, never repo content. |
| `PostToolUse` (Edit/Write) | `post-edit-check` | Async check after file edits. |
| `Stop` | `session-end-reminder` | **Advisory** documentation reminder, fired **at most once per undocumented changeset** (marker keyed on `session_id` stores the reminded file set; re-fires only for new undocumented files after a cooldown, default 45 min via `CLAUDE_SUBTEAMS_DOC_REMIND_COOLDOWN_MIN`). Detects unstaged code changes without `*.md` updates and delivers a hybrid, never-blocking notice: a framed advisory to the model via `additionalContext` ("not a task — surface to the user") + one `systemMessage` line to the operator. Escalates the advisory wording on breaking signals (file deletions, schema/migration files) — see the `doc-quality-gate` skill. Escape hatch: `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1`. See [ADR-009](docs/adr/009-session-end-hybrid-advisory.md) and "Configuration" below. |
| `UserPromptSubmit` | `user-prompt-check` | Async prompt validation. |

When `CLAUDE_SUBTEAMS_MULTI_INSTANCE=1` (see the `multi-instance` skill), additional **opt-in** hooks run — zero effect when unset: `session-start` also registers the instance + injects the roster; `user-prompt-check` / `post-edit-check` also refresh the liveness heartbeat; `coord-notify` (on `UserPromptSubmit` **and** `PostToolUse`) injects a count of unread peer mailbox messages; `coord-session-end` (on `SessionEnd`) deregisters the instance and releases its claims.

## Configuration

### Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK` | Set to `1` to silence the Stop hook's documentation advisory entirely. Use for scratch / experimental work where doc updates are deliberately deferred, or in CI / batch contexts where the cycle does not apply. | unset (advisory active) |
| `CLAUDE_SUBTEAMS_DOC_REMIND_COOLDOWN_MIN` | Minimum age (minutes, positive integer) of the doc-advisory marker before new undocumented files may trigger a re-fire within the same session. Invalid values fall back to the default. | 45 |

### Doc-advisory details

The `session-end-reminder` hook surfaces the doc cycle described in the `decision-context` skill as a **never-blocking advisory, at most once per undocumented changeset** (the marker keyed on the Stop payload's `session_id` stores the file set already reminded about; a re-fire needs both a new undocumented file and an elapsed cooldown — default 45 min, `CLAUDE_SUBTEAMS_DOC_REMIND_COOLDOWN_MIN`; no usable `session_id` → falls back to firing per turn). Delivery is hybrid: the model receives a framed advisory via `hookSpecificOutput.additionalContext` (opens with "Advisory (not a task — surface to the user, don't act now)", ends on a passivity anchor), and the operator sees one fixed `systemMessage` line. Classification:

- **No changes in working tree** → silent pass (does not consume the once-per-session slot).
- **Only `*.md` files changed** → silent pass (docs are what changed).
- **Code + docs both changed** → advisory noting the Decision-context block format, sharpened when breaking signals are present.
- **Code changed without any `*.md` updates** → advisory listing the changed files; escalated wording on breaking signals (deletions, schema/migration files).
- **Not in a git repo** → soft advisory only, no change detection.
- **`CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1`** → fully silent.

Neutral files that never trigger the advisory: `.gitignore`, `.gitattributes`, `.editorconfig`, lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `go.sum`, `poetry.lock`, `uv.lock`, `composer.lock`), `.DS_Store`.

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
