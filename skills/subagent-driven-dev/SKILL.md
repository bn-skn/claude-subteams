---
name: subagent-driven-dev
description: Use when executing implementation plans with independent tasks — fresh subagent per task with two-stage review
---

# Subagent-Driven Development

Execute plan by dispatching a fresh subagent per task, with two-stage review after each: spec compliance first, then code quality.

**Why subagents:** You delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed. They should NEVER inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.

**Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration.

## Briefing Protocol

Every subagent dispatch MUST include:

1. **Task** — full text from plan (NEVER just a reference or summary)
2. **Context** — what has been built so far, project structure, relevant patterns
3. **Files** — exact paths to read, create, or modify
4. **Scope** — what to touch, what to leave alone, constraints
5. **Model** — opus for complex/multi-file tasks, sonnet for routine/single-file tasks

**NEVER make a subagent read the plan file.** Provide full task text directly.

## The Process

### Step 1: Extract All Tasks

1. Read plan file once
2. Extract all tasks with full text and context
3. Note dependencies between tasks
4. Create tracking list for all tasks

### Step 2: Per-Task Cycle

For each task:

1. **Dispatch implementer subagent** with full briefing
2. **Handle implementer status:**
   - DONE: proceed to review
   - DONE_WITH_CONCERNS: read concerns, address if needed, then review
   - NEEDS_CONTEXT: provide missing context, re-dispatch
   - BLOCKED: assess blocker (see Blocker Protocol below)
3. **Dispatch spec reviewer subagent** — does the code match the spec?
   - If no: implementer fixes, spec reviewer re-reviews
   - If yes: proceed to code quality
4. **Dispatch code quality reviewer subagent** — is the code well-built?
   - If no: implementer fixes, quality reviewer re-reviews
   - If yes: mark task complete
5. **Update the plan-of-record:** if a living plan-of-record exists (`docs/plans/active/IMPL-PLAN-*.md`, see the `living-plan` skill), flip the matching acceptance criterion's status (TODO → WIP → DONE, or BLOCKED / TBD where apt) and recompute its Rollup row as the task closes; validate with `scripts/check-plan.sh` before declaring the plan done. This skill is a plan executor too — the matrix must stay in lockstep, not die because `subagent-driven-dev` was chosen over `executing-plans`.
6. Move to next task

### Step 3: Final Review

After all tasks complete:
1. Dispatch final code reviewer for the entire implementation
2. Verify all tests pass together
3. **REQUIRED SUB-SKILL:** Use claude-subteams:finishing-branch

## Blocker Protocol

When a subagent reports BLOCKED:

1. If it is a context problem: provide more context, re-dispatch same model
2. If the task requires more reasoning: re-dispatch with opus
3. If the task is too large: break into smaller pieces
4. If the plan itself is wrong: escalate to the user

**NEVER ignore an escalation or force the same model to retry without changes.**

## Model Selection

| Task Complexity | Model | Signals |
|----------------|-------|---------|
| Routine | sonnet | 1-2 files, complete spec, isolated function |
| Complex | opus | Multi-file, integration, design judgment |
| Review | opus | Needs broad codebase understanding |

**Task complexity signals:**
- Touches 1-2 files with a complete spec: sonnet
- Touches multiple files with integration concerns: opus
- Requires design judgment or broad codebase understanding: opus

## Verification Rules

**MUST verify every changed file yourself.** Do not trust subagent reports. After each task:

1. Check that claimed file changes actually exist
2. Run the tests yourself — do not accept "tests pass" without running them
3. Verify no unintended changes to files outside scope
4. Confirm the implementation matches the spec (that is what the spec reviewer does)
5. If a living plan-of-record exists, confirm its matching criterion + Rollup row were updated for this task — `scripts/check-plan.sh` output is the evidence, not memory.

## Two-Stage Review

**Stage 1 — Spec Compliance (MUST come first):**
- Does the code implement what the spec requires?
- Is anything missing from the spec?
- Is anything extra that was not requested?

**Stage 2 — Code Quality (ONLY after spec compliance passes):**
- Is the code well-structured?
- Are there bugs or edge cases?
- Does it follow project patterns?

**NEVER start code quality review before spec compliance passes.**

## Red Flags

**NEVER:**
- Start implementation on main/master branch without explicit user consent
- Skip either review stage (spec compliance OR code quality)
- Dispatch multiple implementation subagents in parallel (conflicts)
- Make subagent read plan file (provide full text instead)
- Accept "close enough" on spec compliance
- Skip review loops (reviewer found issues = implementer fixes = review again)
- Let implementer self-review replace actual review (both are needed)
- Move to next task while either review has open issues
- Trust subagent file change reports without verification

**ALWAYS:**
- Provide complete briefing with every dispatch
- Verify every changed file yourself
- Run tests yourself after each task
- Use two-stage review in correct order
- Escalate blockers rather than forcing through

## Integration

**Required workflow skills:**
- **claude-subteams:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **claude-subteams:writing-plans** - Creates the plan this skill executes
- **claude-subteams:finishing-branch** - Complete development after all tasks
