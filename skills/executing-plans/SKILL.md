---
name: executing-plans
description: Use when you have a written implementation plan to execute with subagent orchestration and quality gates
---

# Executing Plans

## Overview

Load plan, dispatch each step to an appropriate subagent, run quality gates between steps, report at milestones.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Core principle:** Each plan step becomes a briefing to a subagent. Quality gates between steps catch issues early. Parallel execution where dependencies allow.

## The Process

### Step 1: Load and Review Plan

1. Read plan file completely
2. Review critically — identify questions or concerns about the plan
3. If concerns: Raise them with user before starting
4. If no concerns: Build dependency graph and proceed

### Step 2: Build Dependency Graph

1. Map all tasks and identify which can run independently
2. Group tasks into execution batches:
   - **Batch = set of tasks with no dependencies on each other**
   - Tasks within a batch CAN run simultaneously
   - Batches execute sequentially
3. Identify milestone checkpoints (every 3-5 tasks or at natural boundaries)

### Step 3: Execute Tasks via Subagent Orchestration

For each task in the current batch:

1. **Brief the subagent** using orchestrator-briefing protocol:
   - Task description (full text from plan)
   - Context: what has been built so far, relevant file paths
   - Scope constraints: which files to touch, which to leave alone
   - Model selection: opus for complex/multi-file, sonnet for routine/single-file
   - Expected deliverable: code changes + test results

2. **Dispatch subagent** — one per task
   - Independent tasks within a batch: dispatch simultaneously
   - Use git worktrees for parallel isolation when possible
   - NEVER dispatch parallel subagents that edit the same files

3. **Run quality gates** after each subagent returns:
   - [ ] **Compilation check** — does it build without errors?
   - [ ] **Code review** — dispatch reviewer subagent for spec compliance
   - [ ] **Devils-advocate challenge** (full pipeline, and any non-trivial logic — see using-subteams Section 6) — dispatch devils-advocate to challenge assumptions, edge cases, scale, necessity
   - [ ] **Test verification** — run tests, verify new + existing pass
   - [ ] **UI verification** (if UI changed) — dispatch ui-tester for screenshot comparison and interaction testing
   - [ ] Gate passes: proceed to next task
   - [ ] Gate fails: retry with feedback (max 3 retries)

4. **Retry protocol** (max 3 attempts per gate):
   - Attempt 1: Re-dispatch same subagent with gate failure details
   - Attempt 2: Re-dispatch with more capable model
   - Attempt 3: Break task into smaller pieces, re-dispatch
   - All 3 fail: **STOP and escalate to user** with full context

### Step 4: Milestone Checkpoints

At each milestone (every 3-5 tasks or batch boundary):

1. Summarize what was completed
2. Show test results (total passing/failing)
3. List any concerns or deviations from plan
4. Ask user: "Continue with next batch, or review changes first?"
5. Wait for user response before proceeding

### Step 5: Complete Development

After all tasks complete and all gates pass:
- Announce: "I'm using the finishing-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use claude-subteams:finishing-branch
- Follow that skill to verify tests, present options, execute choice

## When to Stop and Escalate

**STOP executing immediately when:**
1. A gate fails 3 times consecutively
2. Plan has critical gaps preventing starting
3. Subagent reports a blocker it cannot resolve
4. Tests reveal a design flaw (not just a bug)
5. Two subagents produce conflicting changes

**Ask for clarification rather than guessing. NEVER force through blockers.**

## Model Selection Guide

| Task Type | Model | Examples |
|-----------|-------|---------|
| Simple implementation | sonnet | Single file, clear spec, utility function |
| Complex implementation | opus | Multi-file, integration, architecture |
| Code review | opus | Needs broad codebase understanding |
| Test writing | sonnet | Focused scope, clear assertions |
| UI/E2E testing | sonnet | Playwright tests, screenshots, visual regression |
| Codebase analysis | opus | Health check, tech debt discovery, improvement proposals |

## Red Flags

**NEVER:**
- Start implementation on main/master branch without explicit user consent
- Skip quality gates between tasks
- Force through a gate failure more than 3 times
- Dispatch parallel subagents that edit the same files
- Proceed past a milestone without user acknowledgment

**ALWAYS:**
- Build dependency graph before executing
- Use git worktrees for parallel isolation
- Run compilation + review + tests after every task
- Escalate to user after 3 gate failures
- Summarize progress at milestone checkpoints

## Integration

**Required workflow skills:**
- **claude-subteams:using-git-worktrees** - Recommended for Full pipeline and parallel work. For Standard pipeline, a feature branch is sufficient.
- **claude-subteams:writing-plans** - Creates the plan this skill executes
- **claude-subteams:finishing-branch** - Complete development after all tasks
