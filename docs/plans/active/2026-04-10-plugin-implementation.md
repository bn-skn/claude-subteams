# Claude Subteams Plugin — Implementation Plan

> **For agentic workers:** This plan is designed for parallel subagent execution. Independent workstreams can run simultaneously. Use the orchestrator-briefing protocol for each subagent dispatch.

**Goal:** Build the claude-subteams plugin — a team-based development methodology for Claude Code with 43 skills, 8 agents, 6 hooks.

**Architecture:** Fork superpowers 5.0.7 structure. Skills as `skills/<subteam>/<name>/SKILL.md`. Agents as `agents/<name>.md`. Hooks as shell scripts in `hooks/`. Plugin loaded via `~/.claude/plugins/claude-subteams/`.

**Tech Stack:** Markdown (skills, agents), Bash (hooks, scripts), JSON (plugin.json, hooks.json)

**Spec:** `docs/specs/2026-04-10-claude-subteams-design.md` (Approved v5)

**Approach:** Wide, not deep. Each skill is a focused SKILL.md (50-150 lines) with frontmatter, checklist, red flags. Polish iteratively after v1.0 works.

---

## Workstream Overview

```
WS1: Scaffold + Hooks      (blocking — must be first)
WS2: Core skills            (after WS1)
WS3: Process skills         (after WS1, parallel with WS2)
WS4: Quality skills         (parallel)
WS5: Architecture skills    (parallel)
WS6: Security skills        (parallel)
WS7: Design skills          (parallel)
WS8: Prompt-eng skills      (parallel)
WS9: Ops skills             (parallel)
WS10: Specialized skills    (parallel)
WS11: Agents                (parallel with WS4-10)
WS12: Templates + Scripts   (parallel)
WS13: Integration test      (after all others)
```

WS1 is blocking. WS2-WS12 can run in parallel. WS13 is the final gate.

---

## WS1: Scaffold + Hooks (blocking)

### Task 1.1: Plugin manifest and directory structure

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `hooks/hooks.json`

- [ ] **Step 1: Create plugin.json**

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

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p skills/{core,process,quality,architecture,security,design,prompt-eng,ops,specialized}
mkdir -p agents hooks scripts templates docs/{specs,plans/{active,completed}}
```

- [ ] **Step 3: Verify structure**

```bash
find . -type d | sort
```

Expected: all directories from spec Section 3 exist.

- [ ] **Step 4: Commit**

```bash
git init && git add -A && git commit -m "chore: scaffold plugin directory structure"
```

### Task 1.2: Hooks

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/session-start`
- Create: `hooks/pre-commit-gate`
- Create: `hooks/session-end-reminder`
- Create: `hooks/post-edit-check`
- Create: `hooks/pre-push-check`
- Create: `hooks/user-prompt-check`

- [ ] **Step 1: Create hooks.json**

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start",
        "async": false
      }]
    }],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-commit-gate",
          "async": false
        }]
      },
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-push-check",
          "async": false
        }]
      }
    ],
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-edit-check",
        "async": true
      }]
    }],
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-end-reminder",
        "async": false
      }]
    }],
    "UserPromptSubmit": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/user-prompt-check",
        "async": true
      }]
    }]
  }
}
```

- [ ] **Step 2: Create session-start hook**

Read `skills/core/using-subteams/SKILL.md` and output its content as `hookSpecificOutput`. Check for stale BACKLOG.md from previous session.

- [ ] **Step 3: Create pre-commit-gate hook**

Parse stdin JSON for tool input. If command contains `git commit`:
- Check if project has tsconfig.json → run `tsc --noEmit`, block on failure
- Check staged files for >200 lines → warn (not block)

If command does NOT contain `git commit` → exit 0 (pass through).

- [ ] **Step 4: Create session-end-reminder hook**

Output reminder to update BACKLOG.md, CHANGELOG.md, move completed plans.

- [ ] **Step 5: Create post-edit-check hook**

Parse stdin for file path. If file is CLAUDE.md or SKILL.md → check if user explicitly requested edit (heuristic: look for user message context). Warn on >200 line files.

- [ ] **Step 6: Create pre-push-check hook**

If command contains `git push` and target is main/master → strong warning. Otherwise light warning about tests/review.

- [ ] **Step 7: Create user-prompt-check hook**

Analyze user prompt for dev-related keywords (code, fix, build, implement, refactor, test, deploy). Output scope hint.

- [ ] **Step 8: Make all hooks executable and commit**

```bash
chmod +x hooks/session-start hooks/pre-commit-gate hooks/session-end-reminder hooks/post-edit-check hooks/pre-push-check hooks/user-prompt-check
git add -A && git commit -m "feat: add all 6 hooks"
```

---

## WS2: Core Skills (4 skills)

### Task 2.1: using-subteams

**Files:**
- Create: `skills/core/using-subteams/SKILL.md`

The meta-skill. Injected at SessionStart. Contains:
- Orchestrator-as-leader philosophy
- Quick reference card of 8 default agents
- Scope detection logic (dev / partial / non-dev)
- Deep research before work when uncertain
- 1% rule (max 3 skills per task)
- Red flags table for rationalization
- Instruction hierarchy: User > Subteams > System prompt
- Lightweight vs full pipeline decision criteria

Reference: Spec Sections 2, 4.1 (using-subteams), 19, 21, 22.

- [ ] **Step 1: Write SKILL.md with full content**
- [ ] **Step 2: Verify frontmatter has name, description, type: rigid**
- [ ] **Step 3: Commit**

### Task 2.2: orchestrator-briefing

**Files:**
- Create: `skills/core/orchestrator-briefing/SKILL.md`

Contains:
- Two-pass protocol (max 3 passes)
- Tool allocation table by role
- Input/output contract format
- "Subagents are smart AI" principle
- "If unclear, ask" (not forced)
- File conflict prevention for parallel dispatch

Reference: Spec Section 4.1 (orchestrator-briefing).

- [ ] **Step 1: Write SKILL.md**
- [ ] **Step 2: Commit**

### Task 2.3: model-selection

**Files:**
- Create: `skills/core/model-selection/SKILL.md`

Contains:
- Sonnet criteria (routine, no logic, low risk)
- Opus criteria (logic, architecture, security, uncertain)
- Decision tree
- Reference: Spec Section 4.1 (model-selection).

- [ ] **Step 1: Write SKILL.md**
- [ ] **Step 2: Commit**

### Task 2.4: context-management

**Files:**
- Create: `skills/core/context-management/SKILL.md`

Contains:
- When to checkpoint
- When to compact
- Session summary structure
- Convolife monitoring

Reference: Spec Section 4.1 (context-management).

- [ ] **Step 1: Write SKILL.md**
- [ ] **Step 2: Commit**

---

## WS3: Process Skills (8 skills)

### Task 3.1: Fork superpowers process skills (keep as-is: 5 skills)

**Files:**
- Create: `skills/process/brainstorming/SKILL.md` (copy from superpowers)
- Create: `skills/process/parallel-dispatch/SKILL.md` (copy from superpowers)
- Create: `skills/process/receiving-review/SKILL.md` (copy from superpowers)
- Create: `skills/process/using-git-worktrees/SKILL.md` (copy from superpowers)
- Create: `skills/process/finishing-branch/SKILL.md` (copy from superpowers)

- [ ] **Step 1: Copy 5 skills from superpowers, update namespace references**

Source: `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/`

Map:
- `brainstorming/` → `skills/process/brainstorming/`
- `dispatching-parallel-agents/` → `skills/process/parallel-dispatch/`
- `receiving-code-review/` → `skills/process/receiving-review/`
- `using-git-worktrees/` → `skills/process/using-git-worktrees/`
- `finishing-a-development-branch/` → `skills/process/finishing-branch/`

- [ ] **Step 2: Update any internal references from "superpowers:" to "claude-subteams:"**
- [ ] **Step 3: Commit**

### Task 3.2: Fork + extend writing-plans

**Files:**
- Create: `skills/process/writing-plans/SKILL.md`

Copy from superpowers, extend with:
- Plans saved to `docs/plans/active/`, moved to `docs/plans/completed/` when done
- Replace TDD references with "adversarial testing or TDD (user choice)"
- Add subteams agent reference card in plan header

- [ ] **Step 1: Copy, modify, commit**

### Task 3.3: Rewrite executing-plans

**Files:**
- Create: `skills/process/executing-plans/SKILL.md`

Rewrite for subagent orchestration:
- Each plan step → brief to appropriate subagent
- Multiple subagents can run simultaneously
- After each step: compilation check → code-review → test-engineer → next
- Use git worktrees for parallel isolation
- Review checkpoints with user at milestones

Reference: Spec Section 4.2 (executing-plans).

- [ ] **Step 1: Write SKILL.md**
- [ ] **Step 2: Commit**

### Task 3.4: Rewrite subagent-driven-dev

**Files:**
- Create: `skills/process/subagent-driven-dev/SKILL.md`

Copy superpowers subagent-driven-development, rewrite with:
- Briefing protocol from orchestrator-briefing
- Model selection from model-selection
- Two-stage review: spec compliance + code quality
- Verification: read every changed file

Reference: Spec Section 4.2 (subagent-driven-dev).

- [ ] **Step 1: Write SKILL.md**
- [ ] **Step 2: Commit**

### Task 3.5: git-workflow (new)

**Files:**
- Create: `skills/process/git-workflow/SKILL.md`

Contains:
- Branching strategy, conventional commits
- Anti-pattern: commit → test → bug → another commit
- Correct: code → test → verify → commit once
- PR workflow with gh CLI

Reference: Spec Section 4.2 (git-workflow).

- [ ] **Step 1: Write SKILL.md**
- [ ] **Step 2: Commit**

---

## WS4: Quality Skills (7 skills)

### Task 4.1: adversarial-testing (new, replaces TDD)

**Files:**
- Create: `skills/quality/adversarial-testing/SKILL.md`

The flagship quality skill. Contains:
- Philosophy: try to BREAK, not confirm
- 6-step process: receive changes → unit tests → integration tests → adversarial checks → run tests → verdict
- When to invoke / when NOT
- Test types by task (unit, integration, E2E, smoke)
- Red flags table
- Frontmatter: `conflicts-with: [test-driven-development]`

Reference: Spec Section 4.3 (adversarial-testing).

- [ ] **Step 1: Write SKILL.md with full checklist**
- [ ] **Step 2: Commit**

### Task 4.2: code-review (rewrite)

**Files:**
- Create: `skills/quality/code-review/SKILL.md`

Skill = WHAT to check. Agent = HOW.
- Checklist: security, correctness, performance, SOLID
- When to invoke / when NOT
- How to brief code-reviewer agent
- How to handle findings (critical → fix, suggestions → discuss)

Reference: Spec Section 4.3 (code-review).

- [ ] **Step 1: Write SKILL.md**
- [ ] **Step 2: Commit**

### Task 4.3: verification-gate (extend)

**Files:**
- Create: `skills/quality/verification-gate/SKILL.md`

Copy from superpowers, extend with:
- Backup before destructive changes
- Doc freshness check
- Stack-agnostic compilation gate table

Reference: Spec Section 4.3, Section 20.

- [ ] **Step 1: Copy, extend, commit**

### Task 4.4: lint-and-style (new)

**Files:**
- Create: `skills/quality/lint-and-style/SKILL.md`

- [ ] **Step 1: Write SKILL.md covering ESLint, Prettier, editorconfig, language-specific linters**
- [ ] **Step 2: Commit**

### Task 4.5: refactoring (new)

**Files:**
- Create: `skills/quality/refactoring/SKILL.md`

- [ ] **Step 1: Write SKILL.md: when to refactor, safe patterns, DRY at 3+ repetitions**
- [ ] **Step 2: Commit**

### Task 4.6: error-handling (new)

**Files:**
- Create: `skills/quality/error-handling/SKILL.md`

- [ ] **Step 1: Write SKILL.md: retry, circuit breaker, graceful degradation, fix root cause**
- [ ] **Step 2: Commit**

### Task 4.7: test-driven-development (optional, fork)

**Files:**
- Create: `skills/quality/test-driven-development/SKILL.md`

Copy from superpowers TDD skill. Mark as optional.
Frontmatter: `conflicts-with: [adversarial-testing]`

- [ ] **Step 1: Copy from superpowers, add conflicts-with, commit**

---

## WS5: Architecture Skills (6 skills)

### Task 5.1-5.6: Architecture skills (batch)

Create one SKILL.md per skill:

| # | Skill | Key content | Reference |
|---|-------|-------------|-----------|
| 5.1 | `clean-architecture` | CONVENTIONS.md requirement, file rules, dependency direction, max 200 lines | Spec 4.4 |
| 5.2 | `conventions-enforcer` | Validates structure vs CONVENTIONS.md, provides template | Spec 4.4 |
| 5.3 | `api-design` | REST conventions, versioning, Zod validation, OpenAPI | Spec 4.4 |
| 5.4 | `database-design` | Migrations, schema design, query optimization, WAL mode | Spec 4.4 |
| 5.5 | `adr-tracker` | MADR format, when to create, store in docs/adr/ | Spec 4.4 |
| 5.6 | `service-boundaries` | Monolith vs micro decision framework, bounded contexts | Spec 4.4 |

- [ ] **Step 1: Write all 6 SKILL.md files**
- [ ] **Step 2: Commit**

---

## WS6: Security Skills (3 skills)

### Task 6.1-6.3: Security skills (batch)

| # | Skill | Key content | Reference |
|---|-------|-------------|-----------|
| 6.1 | `security-audit` | OWASP Top 10, prompt injection, input validation | Spec 4.5 |
| 6.2 | `dependency-audit` | npm audit, lockfile, license, update strategy | Spec 4.5 |
| 6.3 | `config-and-secrets` | .env validation, gitignore, rotation, protected files | Spec 4.5 |

- [ ] **Step 1: Write all 3 SKILL.md files**
- [ ] **Step 2: Commit**

---

## WS7: Design Skills (3 skills)

### Task 7.1-7.3: Design skills (batch)

| # | Skill | Key content | Reference |
|---|-------|-------------|-----------|
| 7.1 | `design-to-code` | Text spec → code → browser preview → feedback loop. Stack from CONVENTIONS or ask user | Spec 4.6 |
| 7.2 | `design-qa` | design-critic agent dispatch, Nielsen heuristics, a11y check | Spec 4.6 |
| 7.3 | `accessibility` | WCAG 2.1 AA, semantic HTML, keyboard nav, contrast | Spec 4.6 |

- [ ] **Step 1: Write all 3 SKILL.md files**
- [ ] **Step 2: Commit**

---

## WS8: Prompt Engineering Skills (6 skills)

### Task 8.1-8.6: Prompt-eng skills (batch)

| # | Skill | Key content | Reference |
|---|-------|-------------|-----------|
| 8.1 | `subagent-prompt-design` | Tool restriction, output format, minimal context, max 3 hops | Spec 4.7 |
| 8.2 | `prompt-evaluation` | 5-10 test inputs, regression cases, pass/fail tracking | Spec 4.7 |
| 8.3 | `self-optimization` | Iterative improvement cycle for CLAUDE.md/SKILL.md | Spec 4.7 |
| 8.4 | `skill-engineering` | One skill = one job, checklists not prose, NEVER/ALWAYS, red flags | Spec 4.7 |
| 8.5 | `claudemd-engineering` | Max 200 lines, bullets, critical rules on top, monthly review | Spec 4.7 |
| 8.6 | `agent-engineering` | Context engineering, orchestrator patterns, fan-out/fan-in | Spec 4.7 |

- [ ] **Step 1: Write all 6 SKILL.md files**
- [ ] **Step 2: Commit**

---

## WS9: Ops Skills (4 skills)

### Task 9.1-9.4: Ops skills (batch)

| # | Skill | Key content | Reference |
|---|-------|-------------|-----------|
| 9.1 | `ci-cd-pipeline` | GitHub Actions, lint → build → test → deploy, rollback | Spec 4.8 |
| 9.2 | `monitoring-logging` | Structured logging, health checks, alert rules | Spec 4.8 |
| 9.3 | `incident-management` | Response, root cause, postmortem template, action items | Spec 4.8 |
| 9.4 | `scaffolding` | Templates for new services, modules, endpoints, skills, agents | Spec 4.8 |

- [ ] **Step 1: Write all 4 SKILL.md files**
- [ ] **Step 2: Commit**

---

## WS10: Specialized Skills (4 skills)

### Task 10.1: Fork systematic-debugging

- [ ] **Step 1: Copy from superpowers, update namespace, commit**

### Task 10.2-10.4: New specialized skills (batch)

| # | Skill | Key content | Reference |
|---|-------|-------------|-----------|
| 10.2 | `mobile-development` | RN, Flutter, Native, mobile testing, app store | Spec 4.9 |
| 10.3 | `data-engineering` | Zod/pydantic validation, ETL, parser resilience | Spec 4.9 |
| 10.4 | `i18n-localization` | i18next, translation files, date/currency format | Spec 4.9 |

- [ ] **Step 1: Write all 3 SKILL.md files**
- [ ] **Step 2: Commit**

---

## WS11: Agents (8 agents)

### Task 11.1: All 8 agents

**Files:**
- Create: `agents/code-reviewer.md`
- Create: `agents/test-engineer.md`
- Create: `agents/architecture-guard.md`
- Create: `agents/design-critic.md`
- Create: `agents/prompt-evaluator.md`
- Create: `agents/doc-agent.md`
- Create: `agents/researcher.md`
- Create: `agents/security-auditor.md`

Each agent .md follows this structure:
```markdown
---
name: <agent-name>
description: <one-line — what orchestrator sees when choosing>
model: <opus|sonnet>
tools: <list>
---

## Who You Are
<2-3 sentences: role, mindset, approach>

## Your Process
<numbered steps: how you work>

## Output Contract
<standardized format from spec Section 5>

## What You Do NOT Do
<explicit boundaries>
```

Reference: Spec Section 5 (table of all 8 agents with roles, models, tools, output statuses).

- [ ] **Step 1: Write all 8 agent .md files**
- [ ] **Step 2: Commit**

---

## WS12: Templates + Scripts

### Task 12.1: Project templates

**Files:**
- Create: `templates/CONVENTIONS.md`
- Create: `templates/BACKLOG.md`
- Create: `templates/ARCHITECTURE.md`
- Create: `templates/CHANGELOG.md`
- Create: `templates/adr-template.md`

Use formats from Spec Section 7.

- [ ] **Step 1: Write all 5 templates**
- [ ] **Step 2: Commit**

### Task 12.2: Distribution scripts

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/uninstall.sh`
- Create: `scripts/update.sh`

Reference: Spec Section 18.

- [ ] **Step 1: Write install.sh** — clone to ~/.claude/plugins/, add to settings.json, disable superpowers if present
- [ ] **Step 2: Write uninstall.sh** — remove from settings.json, remove directory
- [ ] **Step 3: Write update.sh** — git pull, check version compatibility
- [ ] **Step 4: Make executable, commit**

### Task 12.3: README.md

**Files:**
- Create: `README.md`

Plugin overview, installation, skill list, agent list, philosophy.

- [ ] **Step 1: Write README.md**
- [ ] **Step 2: Commit**

---

## WS13: Integration Test (blocking — after all others)

### Task 13.1: Plugin load test

- [ ] **Step 1: Test plugin loads**

```bash
claude --plugin-dir ~/.claude/plugins/claude-subteams --version
```

- [ ] **Step 2: Test SessionStart hook injects using-subteams**
- [ ] **Step 3: Test skill invocation (invoke 3-4 skills manually)**
- [ ] **Step 4: Test agent spawning (spawn code-reviewer with test brief)**
- [ ] **Step 5: Test pre-commit-gate (attempt commit, verify tsc check)**
- [ ] **Step 6: Test scope detection (send non-dev prompt, verify plugin stays silent)**

### Task 13.2: Fix any issues found

- [ ] **Step 1: Fix and re-test**
- [ ] **Step 2: Final commit**

---

## Execution Strategy

**Parallel dispatch plan:**

```
Round 1: WS1 (scaffold + hooks) — BLOCKING, do first
Round 2: All in parallel:
  - Subagent A: WS2 (core skills, 4 files)
  - Subagent B: WS3 (process skills, 8 files)
  - Subagent C: WS4 (quality skills, 7 files)
  - Subagent D: WS5 + WS6 (architecture + security, 9 files)
  - Subagent E: WS7 + WS8 (design + prompt-eng, 9 files)
  - Subagent F: WS9 + WS10 (ops + specialized, 8 files)
  - Subagent G: WS11 (agents, 8 files)
  - Subagent H: WS12 (templates + scripts + README, 9 files)
Round 3: WS13 (integration test) — BLOCKING, do last
```

**Estimated: ~65 files to create. Each subagent handles 4-9 files.**
