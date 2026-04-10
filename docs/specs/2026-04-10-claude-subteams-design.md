# Claude Subteams Plugin — Design Specification

**Date:** 2026-04-10
**Status:** Approved (v5, 2026-04-10)
**Author:** Bogdan + Claude Opus 4.6
**Reviewed by:** code-reviewer agent (2026-04-10)

## 1. Vision

A Claude Code plugin that implements a **team-based development methodology**. Instead of treating Claude as a single disciplined agent (superpowers approach), Subteams treats Claude as an **orchestrator managing specialized sub-teams** of agents, each with domain expertise, model selection, and standardized communication protocols.

**Fork base:** superpowers 5.0.7 (14 skills, 1 agent, SessionStart hook).

## 2. Core Philosophy

### 2.1 Orchestrator Model

The main agent is a **leader, not a hiding boss**. It:
- Decomposes tasks into delegatable units
- Selects the right sub-team and model for each unit
- Briefs subagents with full context (they see nothing else)
- Verifies every result (never trusts subagent reports blindly)
- Aggregates results and presents to user
- **Understands the work deeply enough to review, fix, and do work itself when needed**
- Does NOT hide behind subagents — if a task is faster to do directly, do it directly
- Cross-module architecture (3+ components interacting) → orchestrator does it itself

### 2.2 Key Principles

1. **Team-based** — skills grouped into sub-teams, each with dedicated agents
2. **Orchestrator-as-leader** — delegate when beneficial, do directly when faster or cross-module. The orchestrator understands the work deeply and can do any task itself — subagents are a tool, not a crutch
3. **Model-aware** — opus for tasks involving logic, architecture, security, or anything uncertain. Sonnet for simple routine tasks (doc formatting, boilerplate, straightforward file edits). Orchestrator decides per task
4. **Adversarial quality** — tester tries to break, not confirm
5. **Briefing protocol** — standardized input/output contract for all subagents
6. **Self-documenting** — project explains itself to any new agent session
7. **Context engineering** — mediocre prompt + great context > great prompt + noisy context

### 2.3 How This Differs From Superpowers

| Aspect | Superpowers | Subteams |
|--------|-------------|----------|
| Focus | Single agent discipline | Team orchestration |
| Testing | TDD (tests before code) | Adversarial (tests after code, tries to break) |
| Agents | 1 (code-reviewer) | 9 specialized |
| Model selection | Inherited | sonnet/opus per task (default: opus) |
| Enforcement | Red flags tables | Red flags + hooks + CI linters |
| Scope | Universal process | Full SDLC (25 areas) |
| Documentation | Specs and plans | Living docs: BACKLOG, CHANGELOG, ADR, CONVENTIONS |

## 3. Plugin Structure

```
~/.claude/plugins/claude-subteams/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── core/
│   │   ├── using-subteams/SKILL.md
│   │   ├── orchestrator-briefing/SKILL.md
│   │   ├── model-selection/SKILL.md
│   │   └── context-management/SKILL.md
│   ├── process/
│   │   ├── brainstorming/SKILL.md
│   │   ├── writing-plans/SKILL.md
│   │   ├── executing-plans/SKILL.md
│   │   ├── subagent-driven-dev/SKILL.md
│   │   ├── parallel-dispatch/SKILL.md
│   │   ├── git-workflow/SKILL.md
│   │   ├── finishing-branch/SKILL.md
│   │   └── using-git-worktrees/SKILL.md
│   ├── quality/
│   │   ├── adversarial-testing/SKILL.md
│   │   ├── code-review/SKILL.md
│   │   ├── receiving-review/SKILL.md
│   │   ├── verification-gate/SKILL.md
│   │   ├── lint-and-style/SKILL.md
│   │   ├── refactoring/SKILL.md
│   │   └── error-handling/SKILL.md
│   ├── architecture/
│   │   ├── clean-architecture/SKILL.md
│   │   ├── conventions-enforcer/SKILL.md
│   │   ├── api-design/SKILL.md
│   │   ├── database-design/SKILL.md
│   │   ├── adr-tracker/SKILL.md
│   │   └── service-boundaries/SKILL.md
│   ├── security/
│   │   ├── security-audit/SKILL.md
│   │   ├── dependency-audit/SKILL.md
│   │   └── config-and-secrets/SKILL.md
│   ├── design/
│   │   ├── design-to-code/SKILL.md
│   │   ├── design-qa/SKILL.md
│   │   └── accessibility/SKILL.md
│   ├── prompt-eng/
│   │   ├── subagent-prompt-design/SKILL.md
│   │   ├── prompt-evaluation/SKILL.md
│   │   ├── self-optimization/SKILL.md
│   │   ├── skill-engineering/SKILL.md
│   │   ├── claudemd-engineering/SKILL.md
│   │   └── agent-engineering/SKILL.md
│   ├── ops/
│   │   ├── ci-cd-pipeline/SKILL.md
│   │   ├── monitoring-logging/SKILL.md
│   │   ├── incident-management/SKILL.md
│   │   └── scaffolding/SKILL.md
│   └── specialized/
│       ├── mobile-development/SKILL.md
│       ├── data-engineering/SKILL.md
│       ├── systematic-debugging/SKILL.md
│       └── i18n-localization/SKILL.md
├── agents/
│   ├── code-reviewer.md
│   ├── test-engineer.md
│   ├── architecture-guard.md
│   ├── design-critic.md
│   ├── prompt-evaluator.md
│   ├── doc-agent.md
│   ├── researcher.md
│   ├── security-auditor.md
│   └── devils-advocate.md
├── hooks/
│   ├── hooks.json
│   ├── session-start
│   ├── pre-commit-gate
│   ├── session-end-reminder
│   └── post-edit-check
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── update.sh
├── docs/
│   ├── specs/
│   └── README.md
└── templates/
    ├── CONVENTIONS.md
    ├── BACKLOG.md
    ├── ARCHITECTURE.md
    ├── CHANGELOG.md
    └── adr-template.md
```

## 4. Sub-teams Detail

### 4.1 Core (always active)

#### using-subteams
**Type:** Meta-skill (rigid)
**Source:** Rewrite of superpowers/using-superpowers
**Trigger:** SessionStart hook

**No prompt injection.** The SessionStart hook does NOT inject methodology text. It only checks for stale state (BACKLOG, active plans).

**Activation is controlled by CLAUDE.md.** The install script adds a 5-line snippet to the project's CLAUDE.md (from `templates/claudemd-snippet.md`):
```markdown
## Development Methodology
For development tasks use the claude-subteams plugin (orchestrator + 9 specialized agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed.
```

This is **user-controlled**: remove the snippet from CLAUDE.md and the plugin is silent. No need to uninstall.

The full using-subteams skill loads on demand via Skill tool. It establishes:
- Orchestrator-as-leader mindset: decompose, delegate, verify
- 1% rule: if any skill might apply, invoke it (max 3 per task)
- Red flags table for rationalization
- Read BACKLOG.md and active plan on session start
- Instruction hierarchy: User > Subteams > System prompt

**Scope detection:** Before applying any development skill, determine if the task is development-related:
- Development task (code, architecture, testing, deployment) → full pipeline
- Partially development (marketing site + code) → only relevant skills
- Non-development (general question, analysis, writing) → plugin stays silent, don't impose process

**Deep research before work:** If the orchestrator is uncertain about technology, API, library, or approach:
- Do research FIRST (WebSearch, WebFetch, read docs, context7 MCP)
- Gather facts before planning or implementing
- Better to spend 30 seconds researching than 10 minutes fixing hallucinations
- This applies to subagents too — give them research tools when task is exploratory

#### orchestrator-briefing
**Type:** Process (rigid)
**Trigger:** Behavioral — embedded in using-subteams, not auto-triggered

Standardized subagent communication protocol.

**Principle: subagents are smart AI agents, not dumb executors.** They can think, research, ask questions, and use any tools the orchestrator grants them. The orchestrator's job is to give them the right tools and enough context to work independently.

**Tool allocation by role:**
| Role | Tools |
|------|-------|
| Code reviewer | Read, Grep, Glob (read-only) |
| Developer | Read, Write, Edit, Bash, Grep, Glob |
| Test engineer | Read, Write, Edit, Bash, Grep, Glob |
| Researcher | Read, Grep, Glob, WebSearch, WebFetch |
| Architecture guard | Read, Grep, Glob, Bash (read-only) |
| Design critic | Read, Grep, Glob, Bash (read-only) |
| Doc agent | Read, Write, Edit, Grep, Glob |

**Two-pass protocol:**

Important: subagents have NO persistent context. Each call starts from scratch. If a subagent needs clarification, the orchestrator re-sends the FULL brief with additional context — not a follow-up message.

```
Pass 1: Orchestrator sends brief → Subagent works
    ├── Subagent has enough context → returns result (done)
    └── Subagent needs clarification → returns questions in output
        │
Pass 2: Orchestrator sends NEW brief (original + answers to questions) → Fresh subagent instance → returns result

Pass 3 (rare): If orchestrator judges it worthwhile — one more re-brief. Max 3 passes total.
```

Do NOT force subagents to ask questions. Simply tell them: "if something is unclear, return your questions in the Questions section." Most of the time, the orchestrator should ask clarifying questions to the USER before delegating — the orchestrator is the leader who coordinates, not a relay.

Subagents MAY do their own research (WebSearch, WebFetch, reading docs) if they have the tools and need more information. They are smart AI agents — they can think, search, and reason independently.

**Input (orchestrator → subagent):**
```
Task: what to do
Context: why, user decisions, constraints
Files: specific paths and line numbers
Scope: what NOT to do
Model: sonnet/opus (default: opus when uncertain)
Tools: what tools you have access to
```

**Output (subagent → orchestrator):**
```
**Task:** brief description
**Status:** done | partial | blocked

### Changes
- `path/to/file.ts` — what changed

### Verification
- tsc --noEmit: OK / FAIL
- Tests: OK / FAIL

### Questions (if any — orchestrator will answer and re-send)
### Notes (if any)
```

Rules:
- Subagent sees NOTHING from the conversation. Brief like a colleague who just walked in.
- Specify concrete files and lines
- Pass user decision context
- Define scope explicitly: what to do, what NOT to do
- Give subagent the tools it needs to work independently
- Allow subagent to ask questions (two-pass protocol)
- For complex tasks: opus. For routine: sonnet. Uncertain: opus.

#### model-selection
**Type:** Reference (flexible)
**Trigger:** When deciding which model to use for a subagent

The orchestrator decides per task. General guidance:

**Sonnet** — simple, routine, low-risk:
- Doc formatting, boilerplate generation, straightforward file edits
- No business logic, no cross-module impact

**Opus** — complex, important, or uncertain:
- Business logic, architectural decisions, bug investigation
- Prompt/skill engineering, security-related work
- Multiple files, cross-module changes
- Anything where you're not sure → opus

#### context-management
**Type:** Process (flexible)
**Trigger:** When context window is filling up, session checkpoint needed

Covers:
- When to create checkpoints (save session summary)
- When to compact (approaching context limit)
- How to structure session summaries for future sessions
- Convolife monitoring

### 4.2 Process (forked from superpowers)

#### brainstorming
**Source:** Keep from superpowers (unchanged)
**Type:** Process (rigid)

Socratic design refinement: one question at a time, 2-3 approaches with trade-offs, sectioned design approval, spec writing.

#### writing-plans
**Source:** Keep from superpowers + extend
**Type:** Process (rigid)

Addition: plans saved to `docs/plans/active/`, moved to `docs/plans/completed/` when done. Plan format includes specific files, line numbers, code snippets, commit messages — no placeholders.

#### executing-plans
**Source:** Rewrite
**Type:** Execution (rigid)

Rewritten for subagent orchestration:
- Each plan step → briefed to appropriate subagent
- Independent steps → parallel dispatch (multiple Agent tool calls in ONE message)
- Multiple subagents CAN run simultaneously — don't wait for one to finish if another is independent
- After each step: tsc → code-review → test-engineer → next step
- Review checkpoints with user at milestones
- Use git worktrees for parallel work isolation when possible

#### subagent-driven-dev
**Source:** Rewrite
**Type:** Execution (rigid)

Rewritten with:
- Briefing protocol from orchestrator-briefing
- Model selection from model-selection
- Two-stage review: spec compliance + code quality
- Verification: read every changed file, don't trust subagent report

#### parallel-dispatch
**Source:** Keep from superpowers (unchanged)
**Type:** Execution (flexible)

For 2+ independent tasks without shared state. Multiple Agent tool calls in one message.

#### git-workflow
**Type:** Process (new)
**Trigger:** When working with git branches, commits, PRs

Covers:
- Branching strategy (feature branches from main)
- Conventional commits format
- Never commit before full pipeline passes
- Anti-pattern: commit → test → find bug → another commit
- Correct: code → test → verify → commit once
- PR workflow with gh CLI

#### finishing-branch
**Source:** Keep from superpowers (unchanged)
**Type:** Process (flexible)

Guides merge/PR/cleanup decisions.

#### using-git-worktrees
**Source:** Keep from superpowers (unchanged)
**Type:** Infrastructure (flexible)

Creates isolated worktrees for feature work.

### 4.3 Quality

#### adversarial-testing
**Type:** Quality (rigid) — NEW, replaces TDD
**Trigger:** After code-review, before commit

Philosophy: tester tries to BREAK the code, not confirm it works.

Pipeline:
1. Receive list of changes + task requirements
2. Write/update unit tests for changed logic
3. Write integration tests if cross-module changes
4. Adversarial checks: edge cases, invalid data, boundary values, race conditions
5. Run `npm test` + smoke test if needed
6. Verdict: **pass** (can commit) or **blocker** (list of problems)

When to invoke:
- Any logic change in src/
- New module, refactoring, handler change, schema change
- Bug fix (verify fix doesn't break other things)

When NOT needed:
- Text/docs/config changes without logic
- Cosmetic changes (CSS, button color)

#### code-review
**Source:** Rewrite
**Type:** Quality (rigid)
**Trigger:** After implementation, before adversarial-testing

Integrated with code-reviewer subagent:
- Pass list of changed files, task context, focus areas
- Reviewer checks: security, correctness, performance, SOLID
- Critical findings: fix before commit
- Suggestions: discuss with user

When to invoke:
- Any logic change (even small — small changes can be cascading)
- New module, refactoring, handler change, schema change, bug fix
- 2+ files touched or src/ of main app/satellites

When NOT needed:
- Text/docs/config without logic
- Typos, single variable rename
- Entries in memories, notes, backlog

#### receiving-review
**Source:** Keep from superpowers (unchanged)
**Type:** Collaboration (flexible)

How to handle review feedback with technical rigor.

#### verification-gate
**Source:** Keep from superpowers + extend
**Type:** Quality (rigid)
**Trigger:** Before any commit, before claiming work is done

Extended with:
- Backup before destructive changes
- Run verification command, read output, confirm BEFORE success claim
- "Evidence before assertions"
- Check that docs are updated

#### lint-and-style
**Type:** Quality (new)
**Trigger:** When writing code, during code review

Covers:
- ESLint configuration and enforcement
- Prettier for formatting
- EditorConfig for cross-editor consistency
- Language-specific linters (pylint, golint, etc.)
- Integration with CI pipeline

#### refactoring
**Type:** Quality (new)
**Trigger:** When code smells detected, when explicitly requested

Covers:
- When to refactor: god-files (>200 lines), circular deps, 3+ duplications
- How to refactor safely: tests first, small steps, verify after each step
- Extract method/class, dependency inversion, repository pattern
- Anti-pattern: refactoring unrelated code while fixing a bug

#### error-handling
**Type:** Quality (new)
**Trigger:** When designing error handling strategy

Covers:
- Retry with exponential backoff for transient failures
- Circuit breaker for external services
- Graceful degradation (fallback behavior)
- Error reporting and structured logging
- Fix root cause, not symptoms (try/catch swallowing is not a fix)

### 4.4 Architecture

#### clean-architecture
**Type:** Architecture (rigid)
**Trigger:** When creating new modules, reviewing structure, architecture guard

Requires CONVENTIONS.md in project root with numbered rules:
- File structure: domain/ → application/ → infrastructure/ → presentation/
- Max 200 lines per file, max 30 lines per function
- One exported thing per file
- Dependency direction: always inward (domain imports nothing)
- Test colocation: thing.ts + thing.test.ts same folder
- Naming: kebab-case files, PascalCase classes, camelCase functions
- No magic strings — constants or enums

Enforcement:
- dependency-cruiser (JS/TS) for import direction validation
- eslint-plugin-import/no-cycle for circular dependency detection
- architecture-guard subagent checks drift during review

#### conventions-enforcer
**Type:** Architecture (rigid) — NEW
**Trigger:** On project setup, during architecture review

Validates project structure against CONVENTIONS.md:
- Checks file sizes (flag >200 lines)
- Checks import directions (flag domain importing infrastructure)
- Checks naming conventions
- Generates report: compliant / violations list

Provides template CONVENTIONS.md for new projects.

#### api-design
**Type:** Architecture (new)
**Trigger:** When designing APIs (REST, GraphQL, internal)

Covers:
- REST conventions: resource naming, HTTP methods, status codes
- Versioning strategy (URL path vs header)
- Request/response schemas (Zod validation)
- OpenAPI spec generation
- Contract-first design between services
- Rate limiting, pagination, error format

#### database-design
**Type:** Architecture (new)
**Trigger:** When designing schemas, writing migrations

Covers:
- Migration files: numbered, reversible, tested
- Schema design: normalization, indexes, constraints
- Query optimization: EXPLAIN, N+1 detection
- Backup strategy before migrations
- SQLite-specific: WAL mode, FTS5, PRAGMA

#### adr-tracker
**Type:** Architecture (new)
**Trigger:** When making architectural decisions

Uses lightweight MADR format:
```markdown
# ADR-NNN: Title
Status: accepted | superseded | deprecated
Date: YYYY-MM-DD
Context: Why (2-3 sentences)
Decision: What we chose (1 sentence)
Consequences: Trade-offs (bullet list)
```

When to create:
- New dependency added
- Public API contract changed
- Choice between two viable patterns
- Technology/framework decision

Store in `docs/adr/`, number sequentially.

#### service-boundaries
**Type:** Architecture (new)
**Trigger:** When deciding monolith vs microservices, designing new services

Covers:
- Decision framework: when to split, when to keep together
- Service boundary design: bounded contexts, data ownership
- Communication patterns: sync (REST/gRPC) vs async (events)
- Shared vs separate databases
- API gateway patterns

### 4.5 Security

#### security-audit
**Type:** Security (rigid)
**Trigger:** Before deployment, when handling secrets/user data

Covers:
- OWASP Top 10 check
- Prompt injection protection (Content Security Policy)
- Input validation at system boundaries
- Authentication/authorization review
- Dependency vulnerability scan (npm audit)

#### dependency-audit
**Type:** Security (new)
**Trigger:** Periodically, when adding/updating dependencies

Covers:
- `npm audit` / `pip audit` — vulnerability scanning
- Lockfile integrity
- License compliance
- Update strategy: patch auto, minor review, major plan
- Removal of unused dependencies

#### config-and-secrets
**Type:** Security (new)
**Trigger:** When handling .env, API keys, credentials

Covers:
- .env validation (all required vars present)
- Secrets never in git (gitignore enforcement)
- Rotation strategy
- Environment-specific configs (dev/staging/prod)
- Protected files: CLAUDE.md, SKILL.md — only editable with user consent

### 4.6 Design (UI/UX)

#### design-to-code
**Type:** Design (new)
**Trigger:** When building UI components, pages, layouts

Pipeline: text spec → code + design system → browser preview → feedback loop

Rules:
- Stack selection: check CONVENTIONS.md first. If not specified, ask the user. If no preference, suggest Tailwind + shadcn/ui (agent-friendly). Vanilla CSS is always an option. Never assume a stack without checking.
- Design tokens in one file (colors, spacing, typography)
- Component inventory: flat list with prop interfaces
- Skip Figma — code IS the mockup
- Consistency via linting (stack-appropriate: eslint-plugin-tailwindcss for Tailwind, stylelint for CSS)

#### design-qa
**Type:** Design (new)
**Trigger:** After UI implementation

design-critic subagent:
- Compares implementation against spec
- Nielsen Norman heuristics evaluation
- Visual consistency check (spacing, colors, typography)
- Responsive behavior verification
- Screenshot comparison via Playwright

#### accessibility
**Type:** Design (new)
**Trigger:** When building UI, during design QA

Covers:
- WCAG 2.1 AA compliance
- Semantic HTML
- Keyboard navigation
- Screen reader compatibility
- Color contrast ratios
- aria-labels, alt texts

### 4.7 Prompt Engineering (meta-level)

#### subagent-prompt-design
**Type:** Prompt Engineering (new)
**Trigger:** When creating/modifying agent prompts in .claude/agents/

Rules:
- Restrict tools to what agent actually needs (fewer tools = fewer mistakes)
- Standardize output format: status, result, errors, metadata
- Keep context minimal — pass only what's needed
- Agent chains max 3 hops (error compounds)
- Explicit handoffs: name WHO you call and WHY

#### prompt-evaluation
**Type:** Prompt Engineering (new)
**Trigger:** When testing skill/agent prompts

Process:
1. Create 5-10 representative test inputs
2. Run skill/agent on each
3. Check outputs against expected results
4. Save as regression test cases
5. Re-run after prompt edits

#### self-optimization
**Type:** Prompt Engineering (new)
**Trigger:** When improving CLAUDE.md, SKILL.md, agent prompts

Iterative improvement cycle:
1. Identify problem (agent doesn't follow rule, produces wrong output)
2. Diagnose root cause (vague instruction? missing context? wrong model?)
3. Propose specific edit
4. Test with regression cases
5. Deploy change

#### skill-engineering
**Type:** Prompt Engineering (new)
**Trigger:** When creating or modifying skills

Rules:
- One skill = one job. Two jobs = two skills.
- Numbered checklists, not prose. Claude follows steps better than paragraphs.
- NEVER/ALWAYS/MUST for critical rules. Soft language gets ignored.
- Red flags tables: "If you see X, do Y instead of Z"
- Test: 5-10 representative inputs as regression cases
- skill-creator is a starting point, always hand-edit output

#### claudemd-engineering
**Type:** Prompt Engineering (new)
**Trigger:** When creating or evolving CLAUDE.md files

Rules:
- Max 200 lines for root CLAUDE.md
- Bullets, not paragraphs
- Critical rules at top
- Rule needing >2 lines of explanation → move to a skill
- Monthly review: delete what Claude does by default
- Subdirectory CLAUDE.md for domain rules (frontend/CLAUDE.md)
- Protected sections marked clearly

#### agent-engineering
**Type:** Prompt Engineering (new)
**Trigger:** When designing multi-agent systems, orchestration

Covers:
- Context engineering > prompt engineering
- Orchestrator + specialists pattern (fan-out / fan-in)
- Minimize token waste (irrelevant context degrades performance)
- Agent boundaries = task boundaries (file, module, concern)
- Log everything for debugging multi-agent failures
- Standardized agent contract (frontmatter + system prompt + output format)

### 4.8 Ops

#### ci-cd-pipeline
**Type:** Ops (new)
**Trigger:** When setting up automated builds, tests, deployments

Covers:
- GitHub Actions / GitLab CI configuration
- Pipeline stages: lint → build → test → deploy
- Environment promotion: dev → staging → production
- Automated rollback on failure
- Deployment notifications

#### monitoring-logging
**Type:** Ops (new)
**Trigger:** When setting up observability

Covers:
- Structured logging (JSON format, correlation IDs)
- Log aggregation (unified sink vs per-service)
- Health check endpoints
- Alert rules (error rate, latency, disk/memory)
- OpenTelemetry tracing for multi-service

#### incident-management
**Type:** Ops (new)
**Trigger:** When system is down, after incidents

Covers:
- Immediate response: identify scope, communicate, mitigate
- Root cause analysis (5 whys, fishbone)
- Postmortem template: timeline, impact, root cause, action items
- Action items tracked in BACKLOG.md
- Blameless culture

#### scaffolding
**Type:** Ops (new)
**Trigger:** When creating new services, modules, bots

Provides templates for:
- New bot/service: folder structure, config, package.json, tsconfig, systemd unit
- New module: file + test + README
- New API endpoint: route + handler + validation + test
- New skill: SKILL.md with frontmatter
- New agent: .md with frontmatter + system prompt + output format

### 4.9 Specialized

#### mobile-development
**Type:** Specialized (new)
**Trigger:** When building mobile apps

Covers:
- React Native / Flutter / Native (Swift, Kotlin)
- Mobile-specific architecture (navigation, state management)
- Platform APIs and permissions
- Mobile testing (Detox, Maestro, XCTest)
- App Store deployment pipeline

#### data-engineering
**Type:** Specialized (new)
**Trigger:** When building ETL, parsers, data pipelines

Covers:
- Data validation (Zod, pydantic)
- ETL patterns: extract → transform → load
- Parser resilience (retry, fallback, partial results)
- Data quality checks
- Batch vs streaming

#### systematic-debugging
**Source:** Keep from superpowers (unchanged)
**Type:** Implementation (rigid)

4-phase root cause process: investigate → analyze patterns → hypothesize → implement. No fixes without root cause.

#### i18n-localization
**Type:** Specialized (new)
**Trigger:** When adding multi-language support

Covers:
- i18n library selection (i18next, intl)
- Translation file format and organization
- Date/time/currency formatting
- RTL language support
- Translation workflow

## 5. Agents

Each agent's `.md` file is its full system prompt — role, approach, and output contract. Detailed personalities are designed during implementation, not in the spec.

| # | Agent | Model | Tools | Sub-team | Role | Output status |
|---|-------|-------|-------|----------|------|--------------|
| 1 | **code-reviewer** | opus | Read, Grep, Glob, Bash | quality | Reviews security, correctness, performance | pass / issues-found |
| 2 | **test-engineer** | opus | Read, Write, Edit, Bash, Grep, Glob | quality | Adversarial testing, writes tests, tries to break | pass / blocker |
| 3 | **architecture-guard** | opus | Read, Grep, Glob, Bash | architecture | Checks drift vs CONVENTIONS.md, dependencies, file sizes | clean / violations-found |
| 4 | **design-critic** | opus | Read, Grep, Glob, Bash | design | Evaluates UI vs spec, Nielsen heuristics, a11y | approved / needs-work |
| 5 | **prompt-evaluator** | opus | Read, Write, Bash, Grep, Glob | prompt-eng | Tests prompts against regression cases | pass / needs-improvement |
| 6 | **doc-agent** | sonnet | Read, Write, Edit, Grep, Glob | core | Two modes: check freshness / write updates | docs-current / updates-done |
| 7 | **researcher** | opus | Read, Grep, Glob, WebSearch, WebFetch | core | Deep research, multi-source, cites sources | findings-ready / insufficient-data |
| 8 | **security-auditor** | opus | Read, Grep, Glob, Bash | security | OWASP Top 10, attack surface, secrets check | secure / vulnerabilities-found |
| 9 | **devils-advocate** | opus | Read, Grep, Glob | quality | Challenges assumptions: "what if?", edge cases, scale, necessity | concerns-raised / looks-solid |

### Standardized output contract (all agents)

Every agent returns this structure:
```
**Task:** brief description
**Status:** [agent-specific status from table above]

### Results (agent-specific sections)
### Questions (if anything is unclear)
### Notes (if any)
```

### Agent spawning

- **8 default agents** — polished prompts, ready to use via `subagent_type`
- **Custom agents** — orchestrator can spawn any agent on-the-fly via Agent tool with custom prompt
- **Foreground or background** — orchestrator decides based on task needs (no prescribed rule)
- **Parallel** — multiple agents can run simultaneously if tasks are independent

## 6. Hooks

### 6.1 session-start
**Event:** SessionStart
**Async:** false

Injects using-subteams meta-skill content. Reads BACKLOG.md and active plan from docs/plans/active/. Also checks for stale state from previous session (un-updated BACKLOG, incomplete plans) as compensation for unreliable Stop hook (user may Ctrl+C).

### 6.2 pre-commit-gate
**Event:** PreToolUse (Bash containing `git commit`)
**Async:** false

Lightweight checks only (shell-feasible):
- Run `tsc --noEmit` — block if compilation fails
- Check for files >200 lines in staged changes — warn (not block)

**Note:** Session-state checks (was code-reviewer called? was test-engineer called?) are enforced behaviorally by the using-subteams meta-skill, NOT by this hook. Hooks are stateless and cannot track session history.

### 6.3 session-end-reminder
**Event:** Stop
**Async:** false

Reminds to:
- Update BACKLOG.md if tasks completed
- Update CHANGELOG.md if features/fixes shipped
- Move completed plan from active/ to completed/
- Create ADR if architectural decisions were made

### 6.4 post-edit-check
**Event:** PostToolUse (Edit or Write on src/** files)
**Async:** true

Lightweight checks (shell-feasible):
- File exceeds 200 lines? → warning
- Grep for forbidden import patterns (e.g., `domain/` importing from `infrastructure/`) → warning
- Writing to CLAUDE.md or SKILL.md without explicit user request? → block

**Note:** Full import graph analysis requires dependency-cruiser in CI. This hook only does pattern-based grep as a fast approximation.

### 6.5 pre-push-check
**Event:** PreToolUse (Bash containing `git push`)
**Async:** false

Warning (not blocking):
- "Pushing to remote. Did tests and review pass this session?"
- If pushing to main/master: stronger warning — "Pushing directly to main. Are you sure?"

### 6.6 user-prompt-check
**Event:** UserPromptSubmit
**Async:** true

Scope detection helper:
- Analyzes user prompt for development-related keywords
- Injects hint to orchestrator: "Development task detected" or "Non-development task — plugin skills not applicable"
- Helps using-subteams decide whether to activate skills or stay silent

### Hooks summary

| # | Hook | Event | Blocking? | Purpose |
|---|------|-------|-----------|---------|
| 1 | session-start | SessionStart | Yes | Inject methodology + check stale state |
| 2 | pre-commit-gate | PreToolUse (git commit) | Yes (tsc) | Compilation check + file size warning |
| 3 | session-end-reminder | Stop | No | Remind to update docs |
| 4 | post-edit-check | PostToolUse (Edit/Write) | Partial | Warn size/imports, block CLAUDE.md edits |
| 5 | pre-push-check | PreToolUse (git push) | No | Warn about tests/review, protect main |
| 6 | user-prompt-check | UserPromptSubmit | No | Scope detection for skills |

## 7. Templates

Plugin ships with project templates that scaffolding skill uses:

### CONVENTIONS.md
Numbered rules for file structure, naming, dependency direction, file size limits.

### BACKLOG.md
```markdown
# Backlog

## In Progress
- [ ] #ID Description — plan: docs/plans/active/name.md

## Next Up
- [ ] #ID Description — spec: docs/specs/name.md

## Ideas (not yet specced)
- Idea description

## Done (last 10)
- [x] #ID Description — YYYY-MM-DD
```

### ARCHITECTURE.md
Project structure, layers, data flow, key decisions (links to ADRs).

### CHANGELOG.md
```markdown
# Changelog

## [YYYY-MM-DD]
### Added
- Feature description
### Fixed
- Bug fix description
### Changed
- Change description
```

### ADR Template
```markdown
# ADR-NNN: Title
Status: proposed
Date: YYYY-MM-DD
Context: Why this decision is needed
Decision: What we chose
Consequences: Trade-offs
```

## 8. Development Pipeline (enforced flow)

```
Task received
    │
    ├── Simple? → Do it → tsc → code-reviewer → test-engineer → commit
    │
    └── Complex? → Questions (all in one message)
                       │
                       ▼
                  Brainstorming → "What If?" challenge → Spec (docs/specs/)
                       │
                       ▼
                  Writing plans → Plan (docs/plans/active/)
                       │
                       ▼
                  Execution (parallel where possible)
                       │
                       ▼
              ┌────────┴────────┐
              ▼                 ▼
        Implementation    Implementation
         (subagent)        (subagent)
              │                 │
              ▼                 ▼
          tsc --noEmit      tsc --noEmit
              │                 │
              ▼                 ▼
         code-reviewer     code-reviewer
              │                 │
              ▼                 ▼
        devils-advocate   devils-advocate (full pipeline only)
              │                 │
              ▼                 ▼
         test-engineer     test-engineer
              │                 │
              └────────┬────────┘
                       ▼
              architecture-guard (if structural changes)
                       ▼
              doc-agent:check (docs freshness)
                       ▼
              doc-agent:write (if docs need update)
                       ▼
              Update BACKLOG, CHANGELOG
                       ▼
              Commit (once, after everything passes)
                       ▼
              Move plan to completed/
```

## 9. Forked vs New Skills Summary

### From superpowers (keep as-is): 7 skills
1. brainstorming
2. parallel-dispatch
3. systematic-debugging
4. receiving-review
5. using-git-worktrees
6. finishing-branch
7. writing-skills (internal use for plugin extension)

### From superpowers (keep + extend): 2 skills
1. writing-plans (+ docs/plans/active/ and completed/ management)
2. verification-gate (+ backup before destructive changes, doc freshness check)

### From superpowers (rewrite): 4 skills
1. using-subteams (was: using-superpowers) — orchestrator model, briefing protocol
2. executing-plans — subagent orchestration with parallel dispatch
3. subagent-driven-dev — briefing protocol + model selection + two-stage review
4. code-review — integrated with code-reviewer agent (skill = WHAT, agent = HOW)

### Replaced: 1 skill
1. adversarial-testing (replaces test-driven-development)

### New: 29 skills
Core: orchestrator-briefing, model-selection, context-management
Process: git-workflow
Quality: lint-and-style, refactoring, error-handling
Architecture: clean-architecture, conventions-enforcer, api-design, database-design, adr-tracker, service-boundaries
Security: security-audit, dependency-audit, config-and-secrets
Design: design-to-code, design-qa, accessibility
Prompt-eng: subagent-prompt-design, prompt-evaluation, self-optimization, skill-engineering, claudemd-engineering, agent-engineering
Ops: ci-cd-pipeline, monitoring-logging, incident-management, scaffolding
Specialized: mobile-development, data-engineering, i18n-localization

### Total: 43 skills, 9 agents, 6 hooks (+ custom agents on-the-fly)

## 10. Plugin Manifest (plugin.json)

```json
{
  "name": "claude-subteams",
  "description": "Team-based development methodology: orchestrator + specialized sub-teams with adversarial testing, architecture enforcement, and full SDLC coverage",
  "version": "1.0.0",
  "author": {
    "name": "Bogdan",
    "url": "https://github.com/bnskn/claude-subteams"
  },
  "keywords": [
    "development-methodology",
    "orchestration",
    "subagents",
    "testing",
    "architecture",
    "code-review"
  ]
}
```

## 11. Skill/Agent Interaction Matrix

```
using-subteams (SessionStart)
  │
  ├── orchestrator-briefing (behavioral, not triggered — embedded in using-subteams)
  ├── model-selection (reference, consulted by orchestrator)
  │
  ├── brainstorming → writing-plans → executing-plans
  │                                        │
  │                                        ├── subagent-driven-dev
  │                                        │     ├── dispatches to: code-reviewer agent
  │                                        │     ├── dispatches to: test-engineer agent
  │                                        │     └── dispatches to: architecture-guard agent (if structural)
  │                                        │
  │                                        └── parallel-dispatch (for independent steps)
  │
  ├── code-review (WHAT to check) → code-reviewer agent (HOW to execute)
  ├── adversarial-testing (WHAT to test) → test-engineer agent (HOW to execute)
  ├── clean-architecture (RULES) → architecture-guard agent (ENFORCEMENT)
  ├── conventions-enforcer (RULES) → architecture-guard agent (ENFORCEMENT)
  ├── security-audit (WHAT to check) → security-auditor agent (HOW to audit)
  ├── design-qa (WHAT to check) → design-critic agent (HOW to evaluate)
  ├── prompt-evaluation (WHAT to test) → prompt-evaluator agent (HOW to test)
  │
  ├── devils-advocate (challenges assumptions in full pipeline, optional in lightweight)
  ├── doc-agent (check freshness + write updates, two modes)
  ├── researcher (deep research before planning, when uncertain)
  │
  └── Custom agents (spawned on-the-fly for tasks without matching default agent)
```

**Rule: Skills define WHAT. Agents define HOW.**
Skills contain checklists, rules, criteria. Agents execute those rules in isolated context.

## 12. Definitions

- **Rigid skill:** Checklist MUST be followed exactly. No deviation. Skipping steps = process failure.
- **Flexible skill:** Principles and guidelines. Adapt to context. The spirit matters, not the letter.
- **Max skills per task:** 3. If more than 3 skills might apply, the orchestrator picks the 3 most relevant. The 1% rule applies to checking, not invoking — check if a skill applies, but don't invoke all 43.

## 13. Error/Rollback Paths

```
Implementation
    │
    ▼
tsc --noEmit ──FAIL──► Fix compilation errors → retry tsc
    │
    OK
    ▼
code-reviewer ──CRITICAL──► Fix critical issues → retry from tsc
    │
    PASS
    ▼
test-engineer ──BLOCKER──► Fix failing tests → retry from tsc
    │
    PASS
    ▼
architecture-guard ──VIOLATION──► Fix violations → retry from tsc
    │
    PASS
    ▼
doc-agent (check) ──STALE──► doc-agent (write) → proceed
    │
    OK
    ▼
Commit
```

**Retry limits:**
- Max 3 retries per gate. After 3 failures → escalate to user: "I've tried 3 times, here's what's failing, how should we proceed?"
- The orchestrator can ask the user clarifying questions at any point — the user is always in the loop for important decisions

**File conflict prevention (parallel subagents):**
- When dispatching parallel subagents, orchestrator MUST assign non-overlapping file sets
- Use git worktrees for true isolation when possible (each subagent in its own worktree)
- If overlap is unavoidable → run sequentially, not in parallel

**Subagent failure handling:**
- Subagent crashes / returns malformed output → retry once with same brief
- Second failure → orchestrator takes over the task directly
- Subagent runs too long → orchestrator can work on other tasks while waiting (background agents)

**Circular dependency prevention:** Skills declare `conflicts-with` in frontmatter (Section 24). Circular skill chains are banned. Linear chains (executing-plans → code-review → code-reviewer agent → security-audit if needed) are allowed — the orchestrator manages the chain, not the skills.

**Subagent self-check principle:** Every subagent MUST verify its own work before returning results:
1. Re-read every file you created/modified — does it match the brief?
2. Run compilation check if applicable (tsc, mypy, go build)
3. Check that all referenced files/functions/paths actually exist
4. Only then return the result to orchestrator

This reduces rework. The orchestrator still verifies (double-check), but the subagent catches obvious mistakes first.

**Post-implementation nuances documentation:**
After any implementation, BOTH subagent and orchestrator capture nuances — things that work but have caveats, workarounds, known limitations, performance constraints, hardcoded values, temporary solutions.

Format (appended to the plan or CHANGELOG):
```markdown
### Implementation Nuances
- `path/to/file.ts:42` — hardcoded timeout (300ms) because API doesn't support configurable timeouts
- `path/to/handler.ts` — works for <1000 records, pagination needed for larger datasets
- Workaround: using `any` cast at line 78 due to library type bug (tracked: github.com/lib/issue/123)
```

**Who captures nuances:**
- Subagent: flags them in the "Notes" section of output contract
- Orchestrator: reviews and adds any the subagent missed
- doc-agent: consolidates into project documentation at session end

## 14. Migration from Superpowers

1. Disable superpowers: `claude settings set enabledPlugins.superpowers@claude-plugins-official false`
2. Enable subteams: `claude settings set enabledPlugins.claude-subteams true`
3. Both plugins CANNOT coexist (overlapping SessionStart hooks, conflicting skill names)
4. Existing CLAUDE.md references to superpowers skills → update to subteams equivalents
5. Existing docs/superpowers/ directories → keep as archive, new specs go to docs/specs/

## 15. Self-Testing Strategy

The plugin tests itself using its own skills:

1. **Skill coverage test:** For each of 43 skills, create 3 test scenarios (simple, medium, edge case). Run via prompt-evaluation.
2. **Hook integration test:** Start session → verify CLAUDE.md snippet activates using-subteams → make edit → verify post-edit-check fires → attempt commit → verify gate behavior → end session → verify reminder.
3. **Agent contract test:** For each of 9 agents, send standardized input → verify output matches contract format (status, changes, verification, questions).
4. **Conflict test:** Load all 43 skills, send ambiguous prompt → verify no more than 3 skills activate, correct ones are prioritized.
5. **Fire test:** Run full pipeline on a real project with a real feature implementation.

## 16. Review Issues Resolution Log

| Issue | Status | Resolution |
|-------|--------|------------|
| C1: pre-commit-gate stateless | Fixed | Behavioral enforcement via using-subteams, hook does tsc only |
| C2: Skill count inconsistent | Fixed | Added "keep + extend" category, corrected counts |
| C3: model-selection contradictory | Fixed | Single rule: default opus, downgrade to sonnet for routine only |
| C4: No plugin.json | Fixed | Added Section 10 |
| I1: orchestrator-briefing trigger | Fixed | Embedded in using-subteams as behavioral protocol |
| I2: post-edit-check import analysis | Fixed | Scoped to grep patterns, full analysis in CI |
| I3: code-review vs code-reviewer overlap | Fixed | Skill = WHAT, Agent = HOW (Section 11) |
| I4: conventions-enforcer vs architecture-guard | Fixed | Same pattern: Skill = RULES, Agent = ENFORCEMENT |
| I5: design-to-code hardcodes Tailwind | Fixed | Default with override via CONVENTIONS.md |
| I6: No error/rollback paths | Fixed | Added Section 13 |
| I7: No migration from superpowers | Fixed | Added Section 14 |
| I8: 43 skills overwhelm matching | Fixed | Max 3 skills per task rule (Section 12) |
| I9: Stop hook unreliable | Fixed | session-start compensates by checking stale state |
| S1: Skill Interaction Matrix | Added | Section 11 |
| S2: Define rigid/flexible | Added | Section 12 |
| S4: 1% rule performance | Added | Max 3 skills per task (Section 12) |
| S6: No self-testing | Added | Section 15 |
| S7: doc-keeper + doc-writer merge | Done | Merged into doc-agent (Section 5.6) |

**Fresh review v3 (2026-04-10):**

| Issue | Status | Resolution |
|-------|--------|------------|
| Infinite retry loops | Fixed | Max 3 retries per gate, then escalate (Section 13) |
| Parallel subagents file conflicts | Fixed | Non-overlapping files + worktree isolation (Section 13) |
| 43 skills bloat SessionStart | Noted | Inject names only, load full skill on demand |
| No escape hatch | Fixed | User can say "skip checks" (Section 22) |
| Behavioral enforcement unverifiable | Accepted | Limitation documented, partially compensated by hooks |
| Opus cost explosion | Noted | Cost awareness, documented sonnet downgrade criteria |
| TDD entirely dropped | Fixed | TDD available as optional skill (Section 23) |
| Subagent crash handling | Fixed | Retry once, then orchestrator takes over (Section 13) |
| Circular skill deps | Fixed | Max depth 2 + skill dependency declarations (Section 24) |
| tsc hardcoded for all languages | Fixed | Stack-agnostic compilation gate (Section 20) |
| No lightweight mode | Fixed | Lightweight vs full pipeline (Section 21) |
| Skill dependency declarations | Added | Section 24 |
| Dropped features undocumented | Fixed | Section 26 |

**User feedback v3 (2026-04-10):**

| Feedback | Resolution |
|----------|------------|
| Subagents have no persistent context | Fixed two-pass protocol: fresh instance with enriched brief |
| Don't force subagents to ask questions | Fixed: "if unclear, ask" — not mandatory |
| Main agent is a leader, not hiding boss | Added to orchestrator model (Section 2.1) |
| Parallel subagents per session | Clarified in executing-plans |
| Git worktrees for isolation | Added to executing-plans and error paths |
| Stack-agnostic development | Added Section 20 |
| User approval: small=do, big=plan first | Added Section 22 |
| Future Codex integration | Added Section 25 |

## 17. Dynamic User Interviewing

Before any significant work, the orchestrator MUST ensure it fully understands the task. This is not optional — it prevents wasted effort and hallucinations.

### Interview process

```
Task received → Orchestrator confident in ALL of these?
  ├── Business logic / purpose → WHY are we doing this?
  ├── Tech stack / constraints → WHAT tools, languages, frameworks?
  ├── Edge cases / error scenarios → WHAT can go wrong?
  ├── Success criteria → HOW do we know it's done?
  ├── Scope boundaries → WHAT is out of scope?
  │
  ├── YES to all → proceed to planning/implementation
  └── NO to any → ask clarifying questions (all in one message)
        │
        ├── User answers → re-evaluate confidence
        └── Still unclear → ask follow-up (max 3 rounds of questions)
```

### Dynamic depth

The interview adapts to task complexity:
- Simple fix ("change button color") → 0 questions, just do it
- Feature ("add authentication") → 3-5 questions (stack, flow, edge cases)
- Architecture ("redesign the data layer") → 5-10 questions (constraints, migration, compatibility)

### Subagent escalation to user

When a subagent returns questions that the orchestrator cannot answer from context:
1. Orchestrator collects the questions
2. Presents them to the user: "My subagent working on X has questions I can't answer from our discussion:"
3. User answers
4. Orchestrator re-briefs the subagent with answers

This is normal and expected. The orchestrator is NOT expected to know everything — asking the user is always better than guessing.

### Red flags (interview skip rationalizations)

| Thought | Reality |
|---------|---------|
| "I know what they want" | You're guessing. Ask. |
| "The code makes it obvious" | Business context is not in code. Ask. |
| "I'll figure it out as I go" | You'll build the wrong thing. Ask first. |
| "They said 'just do it'" | They mean "don't overthink," not "don't ask." Clarify scope. |

## 18. MCP Server Integration

### Recommended MCP Servers

Plugin adapts its capabilities based on available MCP servers. None are required — all are optional enhancements.

| MCP Server | Purpose | Used by skills |
|------------|---------|----------------|
| **context7** | Up-to-date library docs (replaces stale model knowledge) | All development skills, deep research |
| **playwright** | Browser automation, screenshots, E2E testing | design-qa, design-to-code, webapp-testing, adversarial-testing |
| **firecrawl** | Web scraping for research | Deep research phase, data-engineering |

**Detection:** session-start hook checks for available MCP servers and reports capabilities. Skills that need MCP gracefully degrade if unavailable (e.g., design-qa skips screenshot comparison, uses code review only).

### MCP Setup

The plugin does NOT bundle MCP servers — they are installed separately. The install script recommends them:

```bash
# context7 (library docs) — installed as Claude Code plugin
# Already available if plugin is enabled in settings.json

# playwright (browser automation) — installed as Claude Code plugin
# Already available if plugin is enabled in settings.json

# firecrawl (web scraping) — requires API key
# Add to project .mcp.json:
{
  "mcpServers": {
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": { "FIRECRAWL_API_KEY": "<your-key>" }
    }
  }
}
```

**No .env needed for the plugin itself.** MCP servers that need API keys (firecrawl) are configured in the project's `.mcp.json`, not in the plugin. context7 and playwright are Claude Code plugins that need no API keys.

### Plugin .mcp.json

The plugin MAY ship a `.mcp.json` with recommended server configs. Users copy what they need to their project. The plugin never modifies project configs automatically.

## 19. Distribution & Installation

### Install
```bash
# Clone to global plugins directory
git clone https://github.com/bnskn/claude-subteams.git ~/.claude/plugins/claude-subteams

# Or one-liner
curl -fsSL https://raw.githubusercontent.com/bnskn/claude-subteams/main/scripts/install.sh | bash
```

### What install.sh does
1. Clones repo to `~/.claude/plugins/claude-subteams/`
2. Adds plugin to `~/.claude/settings.json` (enabledPlugins)
3. Disables superpowers if installed (cannot coexist)
4. Verifies plugin loads: `claude --plugin-dir ~/.claude/plugins/claude-subteams --version`
5. Prints recommended MCP servers to install

### Uninstall
```bash
~/.claude/plugins/claude-subteams/scripts/uninstall.sh
```
1. Removes plugin from `~/.claude/settings.json`
2. Removes `~/.claude/plugins/claude-subteams/` directory
3. Does NOT remove project-level files (CONVENTIONS.md, docs/, etc.)

### Update
```bash
~/.claude/plugins/claude-subteams/scripts/update.sh
```
1. `git pull origin main`
2. Checks for breaking changes (version comparison)
3. Reports new/changed skills

### No .env required
Plugin uses no API keys. All capabilities come through Claude Code's existing tools and MCP servers.

## 19. Scope Detection

The plugin MUST NOT interfere with non-development tasks. The using-subteams meta-skill includes scope detection:

```
Task received → Is this development?
    │
    ├── YES (code, architecture, testing, deployment, devops)
    │   → Full pipeline: brainstorming → plan → implement → review → test → commit
    │
    ├── PARTIAL (marketing site with code, data analysis with scripts)
    │   → Only relevant skills (e.g., code-review for the code part, skip architecture)
    │
    └── NO (general question, writing, analysis, conversation)
        → Plugin stays silent. No skills invoked. No process imposed.
```

**Detection heuristics:**
- User mentions code, files, bugs, features, deploy → development
- User asks questions about tech → may need research skill only
- User wants text/analysis/advice → not development, stay silent
- When uncertain → ask: "Is this a development task, or should I just help directly?"

## 20. Stack-Agnostic Development

The plugin is NOT tied to any specific tech stack. It works with any language and framework.

**At project start:**
- Determine the project's stack (from package.json, go.mod, requirements.txt, Cargo.toml, etc.)
- Or ask the user: "What stack should we use?"
- Record in CONVENTIONS.md

**Compilation gate adapts to stack:**
| Stack | Compilation check |
|-------|-------------------|
| TypeScript | `tsc --noEmit` |
| JavaScript | `node --check` or ESLint |
| Python | `python -m py_compile` or `mypy` |
| Go | `go build ./...` |
| Rust | `cargo check` |
| None detected | Skip compilation gate |

**Microservices benefit:** Different services CAN use different stacks. A TypeScript bot + a Go parser + a Python ML pipeline is fine. Each service follows its own stack's conventions.

## 21. Lightweight vs Full Pipeline

Not every change needs the full pipeline. Two modes:

**Lightweight mode** (small changes: <3 files, <50 lines, no architectural impact):
```
Code → compilation check → quick self-review → commit
```
No brainstorming, no subagents, no formal plan. Just do it.

**Full pipeline** (significant changes: new features, refactoring, bug fixes affecting logic):
```
Brainstorming → Plan → Present to user → Approval → Implementation → Review → Test → Commit
```

**How to decide:**
- One-line fix, typo, config change → lightweight
- New feature, new module, schema change, multi-file refactor → full pipeline
- When uncertain → ask user: "Should I just do this or plan it first?"

## 22. User Approval Flow

**Small task:** Do it without asking. Show the result.
**Important task:** Present a local plan, wait for user corrections and approval, then execute.

This is NOT micromanagement — it's an engineering gate. "Show me the plan before 3 hours of work" is common sense. "Show me every file before writing" would be micromanagement.

**The user can always:**
- Say "just do it" → skip brainstorming/planning, go straight to implementation
- Say "skip review" → skip code-review and testing gates (escape hatch)
- Say "stop" → abort current pipeline at any point
- Ask questions at any time → orchestrator responds, adjusts plan

## 23. Optional TDD Mode

Adversarial testing (tests after code) is the DEFAULT. But TDD (tests before code) is available as an OPTIONAL skill for users who prefer it.

**When to use TDD:**
- Writing a library with a clear public API → TDD helps define the interface
- User explicitly requests it
- Complex algorithm where test cases help clarify requirements

**When to use adversarial testing (default):**
- Feature development in existing codebase
- Bug fixes
- Refactoring
- Any situation where the implementation shape isn't clear upfront

Both can coexist. The orchestrator picks based on context or user preference.

## 24. Skill Dependencies (frontmatter)

Skills declare their dependencies in SKILL.md frontmatter:

```yaml
---
name: adversarial-testing
description: ...
requires: [orchestrator-briefing]
conflicts-with: [test-driven-development]
sub-team: quality
type: rigid
---
```

This enables:
- Automatic prerequisite invocation
- Conflict prevention (can't invoke adversarial-testing AND TDD on same task)
- Informed max-3 selection (prioritize skills with fewer conflicts)

## 25. Future: External Reviewer Integration

The plugin architecture supports future integration with external AI reviewers:

- **OpenAI Codex** — OAuth/API integration for independent code review (second opinion)
- **Other LLMs** — Gemini, GPT via MCP servers
- **Human reviewers** — GitHub PR review workflow

These are NOT in v1.0. Marked as future work. The architecture supports them through the skill/agent abstraction — a "codex-reviewer" agent would follow the same contract as code-reviewer.

## 26. Dropped Features from Superpowers (Migration Note)

Features from superpowers that were changed or removed, with rationale:

| Superpowers feature | What happened | Why |
|---------------------|---------------|-----|
| **TDD (iron law)** | Made optional (Section 23) | Adversarial testing fits most workflows better; TDD available for those who want it |
| **Single agent model** | Replaced with orchestrator + subteams | Delegation improves quality through specialization |
| **Inherited model** | Replaced with explicit model selection | Opus by default, sonnet for routine — cost/quality optimization |
| **One code-reviewer agent** | Expanded to 9 specialized agents | Different tasks need different expertise |
| **docs/superpowers/ directory** | Replaced with docs/specs/, docs/plans/ | Cleaner organization, living documentation |

## 27. Effectiveness Metrics

Track these to validate the methodology works:

| Metric | How to measure |
|--------|---------------|
| **Bugs caught before commit** | Count of code-reviewer + test-engineer findings per session |
| **Review findings per commit** | Critical / Important / Suggestion counts |
| **Pipeline pass rate** | % of implementations that pass review + test on first try |
| **Tokens consumed** | Per lightweight task vs full pipeline task |
| **Session productivity** | Tasks completed per session |

Display metrics when user asks. No automated collection in v1 — manual tracking via doc-agent or CHANGELOG entries.

## 28. Quality Assurance Process (for the plugin itself)

The plugin was built by parallel subagents. This means potential inconsistencies. Mandatory QA:

### Review cycle (iterate until stable)

```
1. Full review — subagent reads EVERY file, flags issues
2. Fix — orchestrator fixes flagged issues
3. Re-review — fresh subagent verifies fixes
4. Repeat until clean pass
```

### What to check in review

| Check | Why |
|-------|-----|
| Cross-references between skills | Skill A mentions skill B — does B exist? Is the name correct? |
| Agent output contracts match skill expectations | code-review skill expects "pass/issues-found" — does code-reviewer agent return this? |
| Namespace consistency | No remaining "superpowers:" references |
| Frontmatter completeness | Every SKILL.md has name, description, type |
| Checklist quality | Numbered steps, not vague prose. NEVER/ALWAYS/MUST present |
| Red flags tables | Present in rigid skills |
| No hallucinated tools/commands | Every bash command, CLI tool, library mentioned actually exists |
| Forked skills properly adapted | Not just copy-paste from superpowers with broken references |

### Review assignment

Use 3 reviewer subagents in parallel:
- Reviewer A: core + process + quality (20 files)
- Reviewer B: architecture + security + design (12 files)
- Reviewer C: prompt-eng + ops + specialized + agents + templates (22 files)

Each reviewer gets: Read, Grep, Glob tools only. Reports issues in standard format.

## 29. Success Criteria

- [ ] All 43 skills have SKILL.md with frontmatter (including requires/conflicts-with), checklists, red flags
- [ ] All 9 agents have .md with personality, approach, and output contract
- [ ] All 4 hooks work (CLAUDE.md activates, pre-commit gates, Stop reminds, post-edit checks)
- [ ] Plugin loads via `claude --plugin-dir ~/.claude/plugins/claude-subteams`
- [ ] Skills don't conflict (no overlapping triggers, dependency declarations prevent circular chains)
- [ ] Forked superpowers skills maintain original quality
- [ ] New skills follow skill-engineering rules (checklists, NEVER/ALWAYS, red flags)
- [ ] Templates are provided and usable via scaffolding skill
- [ ] CONVENTIONS.md enforcement catches real violations
- [ ] Two-pass protocol works (fresh subagent instance with enriched brief)
- [ ] Scope detection correctly identifies non-development tasks and stays silent
- [ ] Lightweight mode works for small changes (<3 files)
- [ ] Full pipeline works with user approval flow for significant changes
- [ ] Stack-agnostic: compilation gate adapts to project language
- [ ] Parallel subagents: non-overlapping file sets or worktree isolation
- [ ] Retry limits: max 3 per gate, then escalate to user
- [ ] Escape hatch: user can say "skip checks" and plugin respects it
- [ ] Install/uninstall/update scripts work on clean system
- [ ] Fire test: run full pipeline on a real project with a real feature
