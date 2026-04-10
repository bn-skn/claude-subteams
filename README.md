# claude-subteams

A Claude Code plugin that replaces ad-hoc prompting with a structured team methodology: one orchestrator Claude leads specialized sub-teams (code reviewer, test engineer, architecture guard, security auditor, and others), each dispatched with a precise brief, reviewed output, and integrated result — producing code that survives production.

## Philosophy

You are the **orchestrator**. You understand the work deeply, set direction, delegate parallelizable or specialized tasks to sub-team agents, verify every result yourself, and never hide behind subagents. Sub-teams are smart agents, not dumb executors — brief them with full context and they return structured, verifiable output.

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bnskn/claude-subteams/main/scripts/install.sh)
```

Or clone and run manually:

```bash
git clone https://github.com/bnskn/claude-subteams ~/.claude/plugins/claude-subteams
bash ~/.claude/plugins/claude-subteams/scripts/install.sh
```

## Skills

| Sub-team | Skill | Description |
|---|---|---|
| core | `using-subteams` | Orchestrator meta-skill — methodology, pipeline, red flags. Loaded at session start. |
| core | `orchestrator-briefing` | Subagent communication protocol. Use before every Agent tool call. |
| core | `model-selection` | Guide for choosing sonnet vs opus per task type. |
| architecture | `clean-architecture` | Enforces layered architecture, dependency direction, and file size limits. |
| architecture | `conventions-enforcer` | Validates project structure against CONVENTIONS.md. |
| design | `design-to-code` | Pipeline from text spec to working code with browser preview and feedback loop. |
| design | `design-qa` | Compares implementation against design spec; heuristic evaluation and visual consistency. |
| ops | `ci-cd-pipeline` | Sets up and modifies CI/CD pipelines and environment promotion strategies. |
| process | `brainstorming` | Explores intent and requirements before any implementation. Use before creative work. |
| quality | `code-review` | Structured review checklist: security, correctness, performance, SOLID principles. |
| quality | `adversarial-testing` | Writes tests designed to break the code — edge cases, race conditions, boundary violations. |

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

## Hooks

| Event | Hook | Purpose |
|---|---|---|
| `SessionStart` | `session-start` | Injects `using-subteams` methodology into context; warns about stale in-progress backlog items. |
| `PreToolUse` (Bash) | `pre-commit-gate` | Runs tsc / mypy / go build before any git commit; warns on files over 200 lines. |
| `PreToolUse` (Bash) | `pre-push-check` | Safety check before git push. |
| `PostToolUse` (Edit/Write) | `post-edit-check` | Async check after file edits. |
| `Stop` | `session-end-reminder` | Reminds to update BACKLOG.md, CHANGELOG.md, and ADRs before ending session. |
| `UserPromptSubmit` | `user-prompt-check` | Async prompt validation. |

## Templates

Project scaffolding templates in `templates/`:

| File | Purpose |
|---|---|
| `CONVENTIONS.md` | Coding conventions: structure, naming, limits, error handling. |
| `ARCHITECTURE.md` | Architecture documentation: diagram, layers, data flow, ADR links. |
| `BACKLOG.md` | Task tracking: in progress, next up, ideas, done. |
| `CHANGELOG.md` | Keep-a-Changelog format for release notes. |
| `adr-template.md` | Lightweight MADR for architectural decisions. |

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
