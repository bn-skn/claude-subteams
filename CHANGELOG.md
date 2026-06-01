# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.13.0] - 2026-06-01

### Changed
- **cross-review — native default model.** GPT critics no longer hardcode `gpt-5.5`. By default they pass NO `-m` flag, so Codex uses whatever model the Codex CLI is configured to use (`~/.codex/config.toml`) — upgrade the model natively in Codex and the critics inherit it with zero plugin edits. `CROSS_REVIEW_MODEL` optionally pins a specific model. Reasoning effort still defaults to `high` (Codex's own default is "none", which yields shallow reviews).

### Added
- **cross-review — run any agent through GPT (opt-in).** Beyond the two standing GPT critics, any specialist role (security-auditor, test-engineer, architecture-guard, design-critic, …) can be cross-checked on Codex/GPT via the same generic invocation pattern, on explicit request.
- **using-subteams — cross-model review wired into the pipeline.** Full-pipeline Step 6 now also dispatches `gpt-code-reviewer` + `gpt-devils-advocate` alongside the Claude reviewers when Codex is available (4 critics: 2 Claude + 2 GPT); falls back to Claude-only when Codex is down. Standard-pipeline review can optionally add the GPT reviewer. Never blocks the pipeline.

## [1.12.1] - 2026-06-01

### Changed
- **cross-review** — removed the quota-saving "default 1 GPT call / deep mode" split. `/cross-review` now dispatches the FULL critic set by default — both Claude critics (`code-reviewer` + `devils-advocate`) AND both GPT critics (`gpt-code-reviewer` + `gpt-devils-advocate`) — for complete cross-model coverage. Quota guidance reworded from a rationing constraint to awareness-only: run all critics whenever cross-review fires; pause Codex only if the human reports interactive ChatGPT being throttled (a reaction to a real signal, not a pre-emptive cap). Dropped the one-attempt-per-`/rescue`-session cap (no-auto-retry-on-failure remains, for reliability not rationing).

## [1.12.0] - 2026-06-01

### Added
- **cross-model review** — a second critic on a DIFFERENT model (OpenAI Codex / GPT-5.5) to break Claude's model-monoculture blind spots.
  - **gpt-code-reviewer** + **gpt-devils-advocate** agents — shell out to `codex exec` (read-only sandbox) for cross-model code review and architectural challenge. Paired with the Claude critics but with deliberately ORTHOGONAL prompts (concurrency / numeric / platform / spec-drift bugs; abstraction / contract / failure-model challenges) so the second model adds coverage instead of echoing Claude. Prompts are open-ended ("report anything material," not a closed checklist) with an `other_findings` channel for independent discoveries.
  - **cross-review skill** — `/cross-review` (Claude + GPT critics in parallel, merged by a deterministic escalation rule + an intersection heuristic with severity normalization) and `/rescue` (Codex diagnoses a stuck bug, read-only, human implements). Default mode = ONE GPT call to preserve ChatGPT Plus quota; deep mode = two, reserved for security-critical / breaking / new-service reviews.
  - **Model/effort policy:** strongest model at high reasoning effort (`gpt-5.5` + `model_reasoning_effort=high`), configurable via `CROSS_REVIEW_MODEL` / `CROSS_REVIEW_EFFORT` env vars — a single override point for both agents. This is deliberate: Codex defaults to NO reasoning effort, which yields shallow quick-scan reviews.
  - Graceful and safe: availability-checked before every call, never blocks the main pipeline when Codex is down, one attempt per call (shared quota), read-only sandbox always. Verified working from the dev environment (Codex CLI 0.135.0, gpt-5.5 at high effort).

## [1.11.0] - 2026-06-01

### Added
- **llms-install.md** — AI-readable installation protocol. A user hands the file to a coding agent ("@llms-install.md install this plugin"); the agent runs pre-flight capability/dependency checks, executes the installer (curl one-liner or clone path), verifies the JSON state, and reports. Designed for honesty over a happy path: declares required harness capabilities (shell / outbound network / process-substitution) up front, treats a `<()` syntax error as "use the clone path" rather than an install failure, gates on already-installed state (fresh-install vs re-run), reports "files installed — functionally unverified" instead of overclaiming (functional confirmation is the post-reload smoke test), and surfaces installer `WARNING:` lines verbatim.
- **llms-uninstall.md** — companion uninstall protocol: confirm installed → run uninstall.sh → verify removal across all three state files + the plugin directory → report.

### Changed
- **README** — added an "Install via an AI agent" subsection pointing to llms-install.md.

## [1.10.0] - 2026-06-01

### Added
- **doc-quality-gate skill** — model-side change classifier (cosmetic / feature / architectural / breaking) with per-class documentation requirements and doc-agent dispatch rules. Maps the hook's file signals to a class, then defines what docs each class needs. Delegates decision-block format and field discipline to `decision-context` (no duplication). Includes an honest scope note: the hook reminds via file signals, it does not verify documentation content — real breaking-change verification is the doc-agent audit plus judgment.
- **session-end-reminder hook — breaking-signal escalation.** The Stop hook now detects two reliable, asymmetric file signals — deletions (`git status D`) and schema/migration files (`migrations/`, `.sql`, `.prisma`, `schema.`) — and escalates its enforcement message to the full breaking-change checklist (CHANGELOG + descriptive rewrite + decision block + migration guide + doc-agent audit). Deliberately NARROW: routine additive signals (dependency manifests, new routes, `.proto`, `plugin.json`) do NOT trigger escalation — they flow through the standard reminder — to avoid false-positive fatigue that would push users to disable the hook entirely. Escalation also fires in the code+docs case when `CHANGELOG.md` is missing. Escape hatch (`CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1`) and the 2-attempt cap are unchanged.

### Changed
- **doc-agent** — added a third mode: breaking-change audit. Verifies that a breaking/architectural change has all required artifacts present and current: migration guide (if integrations break), API/contract docs, CHANGELOG entry, rewritten (not appended) descriptive section, and a decision-context block with non-empty Alternatives and Risks.

## [1.9.0] - 2026-06-01

### Added
- **live-research skill** — keeps the orchestrator and agents from coding against stale training-data knowledge of fast-moving APIs. Two command surfaces (`/research <question>`, `/whatsnew <library> [N months]`) plus a source-priority ladder (Context7 → Firecrawl → WebSearch → Serper) with graceful degradation. Architecture: the ORCHESTRATOR (main window, which holds MCP tools) fetches Context7/web docs and injects them into the researcher's brief as a `[Live Docs]` block — the dispatched researcher agent synthesizes them (it cannot call MCP tools directly, by tool-allowlist design). Portable: never hardcodes a Context7 MCP prefix; degrades to web sources when Context7 is absent.

### Changed
- **researcher agent** — Process step 3 now consumes Context7 docs injected via its brief (orchestrator-fetched) before generic web search, instead of attempting MCP calls it cannot make.
- **systematic-debugging** — added a category-gated live-research trigger: failures crossing a library/SDK/external-API boundary run live-research at Phase 1 (verify the API model is current before forming more hypotheses); internal-logic bugs (null, type, control flow, race) skip it and proceed straight to architecture questioning. Prevents wasting an opus research pass on bugs that were never API-knowledge issues.

## [1.8.0] - 2026-06-01

### Added
- **project-scaffold skill** — interactive wizard that bootstraps a brand-new project's documentation/config skeleton from one command. Gathers project parameters (name, goal, stack, frameworks, persistence, external APIs, build/test/lint/run/dev/install commands, repo URL, license) and assembles `CLAUDE.md`, `README.md`, `.gitignore`, `docs/SYSTEM.md`, plus `docs/plans/{active,completed}/` and `docs/adr/` seeds — reusing the existing `templates/*` for CONVENTIONS/ARCHITECTURE/BACKLOG/CHANGELOG/ADR. Safety: `ls -A` empty-directory check with a benign-file allowlist (`.git`, `.gitignore`, `LICENSE`, `README.md`, `.github`, `.DS_Store`) that never clobbers existing files, and a hard abort on real source/config (`package.json`, `pyproject.toml`, `go.mod`, `src/`, source files). Complements — does not overlap — the `scaffolding` skill: project-scaffold bootstraps a whole new project once; `scaffolding` adds components repeatedly. First of the v1.8 line, shipped incrementally.
- **templates/project-init/** — new bootstrap templates: two-layer `SYSTEM.md` (living system description + append-only decisions journal in the `decision-context` block format), a full project `CLAUDE.md`, a `README.md`, and a stack-agnostic `dot-gitignore` covering Node/TypeScript, Python, Go, OS, and editor artifacts.

### Changed
- **scaffolding** — "Project docs" Quick Reference row now points to the `project-scaffold` skill (single source of truth for initial project docs); added a "use project-scaffold first" note to When-to-Use to prevent trigger collision.
- **templates/ARCHITECTURE.md** — fixed the Related ADRs link from `docs/adrs/001-title.md` (plural, nonexistent) to `docs/adr/000-adr-template.md`, matching the directory the scaffold creates.

## [1.7.1] - 2026-05-21

### Fixed
- **install.sh**: marketplace description created by the install script said "9 specialized sub-team agents" — stale since v1.3.0 (developer) and v1.5.0 (ui-tester, improvement-agent). Now reads "12 specialized sub-team agents", matching reality. Cosmetic — does not affect install behavior, only the description text written to the user's local `marketplace.json`.

## [1.7.0] - 2026-05-20

### Added
- **session-end-reminder hook — now enforcing.** Smart Stop hook that detects unstaged code changes in the working tree and blocks `Stop` (exit 2) when non-doc files changed without any `*.md` updates. Behavior:
  - No changes / only docs / lock files → silent pass.
  - Code + docs both changed → soft reminder to confirm Decision-context block.
  - Code without doc updates → block with explicit instructions referencing the `decision-context` skill.
  - Counter resets on each new commit (HEAD change). After 2 enforcement attempts in the same HEAD state, allows stop with audit warning (prevents infinite loops if model cannot comply).
  - Not a git repo → soft checklist only.
- **CLAUDE_SUBTEAMS_SKIP_DOC_CHECK env var** — escape hatch to disable doc-enforcement for scratch / experimental work, CI contexts, or legitimate skip cases. Documented in `README.md` under "Configuration".
- **decision-context skill — new "End-of-Work Cycle" section.** Explains the start-of-work / during / end-of-work cycle for cases when no commit is happening (research, planning, debugging). Documents the Stop hook backstop and escape hatch. Adds two new Red Flags: stale descriptive docs, repeated Stop hook blocks.
- **decision-context skill — checklist for descriptive docs.** Step 4 of Workflow now mandates updating the descriptive part of the docs (top of `SYSTEM.md` or equivalent) by overwriting when affected, not just appending to the journal. "Stale descriptive docs are worse than missing ones."

### Changed
- **README.md** — Stop hook row in the Hooks table now describes enforcement behavior. New "Configuration" section documents `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK` and the full Stop-hook decision tree (no changes / docs only / code + docs / code only / not a repo / escape hatch active). Lists neutral files that never trigger enforcement.

## [1.6.0] - 2026-05-20

### Added
- **decision-context skill** — mandatory "decision context" block for every non-trivial change documented in `SYSTEM.md`, `CHANGELOG.md`, session journals, or postmortems. Five fixed labels: Decision / Why / Alternatives / Risks / Linked. Lightweight everyday companion to `adr-tracker` (which remains reserved for project-defining choices). Includes good/bad examples, field discipline, workflow, and red flags. Future-self insurance against cargo-cult and lost context six months later.
- Skill count: 48 → 49.

### Changed
- **git-workflow** — clarified commit-body rule. Was: "Body explains WHY, not WHAT". Now: for non-trivial commits the body MUST mirror the decision-context block from the project's decisions journal (cross-link to `decision-context` skill). Cosmetic / patch-bump commits still get a one-line body.
- **plugin.json** — bumped version `1.4.2` → `1.6.0` (was out of sync with CHANGELOG which already documented 1.5.0; resyncing in this release).

## [1.5.0] - 2026-05-11

### Added
- **ui-tester agent** (sonnet) — browser-based UI/E2E testing via Playwright CLI (not MCP). Takes screenshots, clicks buttons, fills forms, evaluates visual results. Works locally and generates CI-ready `.spec.ts` test files. Two modes: ad-hoc quick checks and standard test suite generation. Write access restricted to test files and config only — never touches source code.
- **improvement-agent** (opus) — proactive codebase analyst. Examines 7 dimensions: code health, dependency health, test coverage gaps, architecture drift, performance signals, log/error patterns, developer experience. Returns prioritized proposals (P0-P3) with file:line references. Read-only — never writes code. Explicit Bash constraints: forbidden commands documented.
- **ui-testing skill** — dispatch protocol for ui-tester agent with 3 testing levels (quick check, standard, full E2E). Includes CI integration template for GitHub Actions, token budget guidelines, and brief template.
- **codebase-improvement skill** — dispatch protocol for improvement-agent with 3 analysis modes (quick scan, standard, deep audit). Includes integration patterns and developer agent chain.
- Agent count: 10 → 12. Skill count: 46 → 48.

### Changed
- **executing-plans** — added UI/E2E testing and codebase analysis to Model Selection Guide. Added ui-tester as optional quality gate after UI changes.
- **verification-gate** — added "UI intact" row to Common Verification Failures table (screenshot comparison as evidence).
- **using-subteams** — version bumped to 1.5.0, description updated to 12 agents, improvement-agent model corrected to opus.

## [1.4.2] - 2026-05-03

### Fixed
- writing-plans: removed phantom "worktree created by brainstorming" reference
- finishing-branch: cleanup scope now correctly includes Options 1, 2, and 4
- brainstorming HARD-GATE: scoped to brainstorming phase only (no longer conflicts with pipeline skip)
- executing-plans + subagent-driven-dev: worktrees changed from REQUIRED to recommended
- brainstorming + writing-plans: directories created if they do not exist


## [1.4.1] - 2026-05-03

### Added
- **Standard pipeline** between Lightweight and Full: Plan → Branch → Implement → Single Review → Test → Commit → Merge. For moderate tasks (3-8 files, single-module).
- **Branch rule**: main = production, all development in feature branches. Worktrees for parallel subagent work.
- **Triple Review conflict resolution**: project conventions > general practices, structural > tactical, approach-level challenges escalate to user.
- **Brainstorming degradation clause**: after 3 non-converging rounds, summarize and offer to move forward.

### Changed
- "Maximum 3 skills" clarified to mean specialist skills on top of pipeline core.


## [1.4.0] - 2026-05-03

### Added
- **Interview-based brainstorming** — phased dialogue (Purpose → Context → Deepening) replaces old question-dump approach. No artificial limit on rounds; stop criterion is quality of understanding.
- **Orchestrator self-escalation** (Section 9) — orchestrator must escalate to user when facing blockers, impossible constraints, or decisions outside authority. Not just subagents.
- **Silent substitution prevention** — new Red Flag + Critical Rules #19-#20: never silently switch from an agreed approach. Present obstacle and options, let user decide.

### Changed
- Brainstorming skill rewritten: interview process with phases, per-round summaries, readiness checklist
- Section 7 (Dynamic User Interviewing): removed artificial "max 3 rounds" limit, aligned with brainstorming interview philosophy
- Section 9 renamed from "Subagent Escalation to User" → "Escalation to User (Subagents AND Orchestrator)"
- Red Flags Table: +2 new entries (silent substitution, autonomous handling)
- Critical Rules: +2 new rules (#19 silent substitution, #20 escalation duty)


## [1.3.0] - 2026-05-03

### Added
- **Developer agent** — implementation specialist with coding standards: modular code, minimal diffs, no god files, preserve project style, don't break other logic, document risks
- **Full Pipeline v2** in using-subteams:
  - Step 3: Plan Defense (devils-advocate reviews plan before implementation)
  - Step 4: Backup tag before implementation
  - Step 6: Triple Review (code-reviewer + architecture-guard + devils-advocate in parallel)
  - Step 10: Mandatory risk & nuance documentation
  - Step 12: Cleanup (remove backup tag, worktree, move plan to completed)
- 6 new Critical Rules (#13-18): preserve style, no god files, minimal changes, don't break logic, document risks, backup tags
- Mandatory "Risks & Nuances" section in writing-plans skill

### Changed
- Agent count: 9 → 10
- Pipeline: reactive (implement → review) → proactive (plan → defend → backup → implement → triple review → test → verify → document → finish → cleanup)
- Devils-advocate: now used twice — once for plan defense, once for code challenge

## [1.2.0] - 2026-05-03

### Fixed
- **Critical:** Renamed marketplace from "claude-subteams" to "bn-skn" to avoid cache recursion bug (#34200) when marketplace name == plugin name
- install.sh: now creates marketplace wrapper and registers in known_marketplaces.json
- install.sh: jq dependency check with warning at install time
- install.sh: git dependency check (hard fail)
- uninstall.sh: cleans known_marketplaces.json
- All scripts: migration from old marketplace name (claude-subteams@claude-subteams → claude-subteams@bn-skn)

### Changed
- Plugin key changed: `claude-subteams@claude-subteams` → `claude-subteams@bn-skn`
- Version bumped to 1.2.0
## [1.1.0] - 2026-05-02

### Fixed
- All hooks: jq availability check with graceful exit if missing
- All hooks: printf instead of echo for variable output (handles -e/-n)
- pre-commit-gate: IFS= read -r for filenames with spaces/backslashes
- install.sh/uninstall.sh: HOME safety check (prevent rm -rf on empty HOME)
- install.sh: version read from plugin.json instead of hardcoded
- install.sh: CLAUDE.md snippet checks existence, skips duplicates
- INSTALL.md: version updated to 1.1.0
- **Critical:** uninstall.sh and update.sh used wrong plugin path — could not uninstall or update after install.sh
- **Critical:** uninstall.sh used wrong enabledPlugins key (`claude-subteams` instead of `claude-subteams@claude-subteams`)
- **Critical:** pre-commit-gate failed on systems using nvm — npx not in PATH for hook shell
- pre-commit-gate matched any command containing "git commit" string (false positives)
- pre-push-check matched branch names containing "main"/"master" as substrings
- pre-commit-gate warning said "staged files exceed 200 lines" when it checks total file size
- user-prompt-check triggered on generic words (fix, test, code) — high false positive rate
- uninstall.sh now also cleans installed_plugins.json (previously left stale entry)
- update.sh now migrates from old install path automatically

### Added
- Timeout on all synchronous hooks (prevents session hang if npx/tsc freezes)
- nvm sourcing in pre-commit-gate (graceful fallback if npx not found)
- CHANGELOG.md
- `claude --plugin-dir` dev workflow in README
- Environment requirements documented (nvm, jq)

### Changed
- Version bumped to 1.1.0
- plugin.json: added repository, license, homepage fields
- Dynamic skill count check in install.sh (no hardcoded number)
- Researcher agent: documented MCP dependency for WebSearch/WebFetch

## [1.0.0] - 2026-04-10

### Added
- Initial release: 9 agents, 46 skills, 6 hooks
- install.sh, uninstall.sh, update.sh scripts
- Templates: CONVENTIONS.md, ARCHITECTURE.md, BACKLOG.md, CHANGELOG.md, ADR template
- Hooks: pre-commit-gate, pre-push-check, post-edit-check, session-start, session-end-reminder, user-prompt-check

