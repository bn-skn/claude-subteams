---
name: executing-plans
description: Use when you have a written implementation plan to execute with subagent orchestration and quality gates
---

# Executing Plans

## Overview

Load plan, dispatch each step to an appropriate subagent, run quality gates between steps, report at milestones.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Core principle:** Each plan step becomes a briefing to a subagent. Quality gates between steps catch issues early. Parallel execution where dependencies allow.

**Plan-of-record upkeep:** if the work has a living plan-of-record (`docs/plans/active/IMPL-PLAN-*.md`, see the `living-plan` skill), flip the matching acceptance criterion's status (TODO → WIP → DONE, or BLOCKED / TBD where apt) and recompute its Rollup row as each task closes — keeping it in lockstep with `BACKLOG.md` / `CHANGELOG.md`. Validate with `scripts/check-plan.sh` before declaring the plan done.

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

**Interactive mode (default):**
4. Ask user: "Continue with next batch, or review changes first?"
5. Wait for user response before proceeding

**Autonomy mode (explicit grant + fresh run record ONLY — see `## Autonomy Mode`):**
4. Run the non-blocking **evidence checkpoint**: `scripts/autonomy-check.sh` (≥1 deterministic exit code); record the script-authored `AUTONOMY_CHECKPOINT:` line.
5. Continue to the next batch **unless a blocker class fires** (cap-exceeded / out-of-scope — structurally blocked by the `autonomy-gate` hook before the edit; or external-evidence-required). No human pause mid-run.

### Step 5: Complete Development

After all tasks complete and all gates pass:
- Announce: "I'm using the finishing-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use claude-subteams:finishing-branch
- Follow that skill to verify tests, present options, execute choice

## Autonomy Mode

> **This section applies ONLY inside an explicitly granted autonomy run. Interactive readers: skip it — nothing here changes the default ask-and-wait flow.**

Autonomy is the manual pipeline minus the human pause, plus bounded, evidence-carrying checkpoints. It is never ambient.

**Activation contract.** A run is autonomous only when BOTH hold: (1) the operator grants it explicitly **in the current message**, and (2) a run record is written into the active contract (`living-plan` §3a: grant, criteria snapshot, scope, base commit, session, expiry, caps). No record, a stale/expired one, or a session mismatch → interactive: ask and wait. **Never continue on a remembered grant.**

**Enforcement layers (honestly labeled):**
- **HOOK = enforcement.** `autonomy-gate` (PreToolUse) blocks an out-of-scope or cap-exceeding edit *before* it lands for the file-writing tools (Edit/Write/MultiEdit/NotebookEdit — it resolves `tool_input.file_path`, or `tool_input.notebook_path` for NotebookEdit, and pre-checks it against scope before the edit runs; both the target path and the record path it's compared against are canonicalized — `realpath -m`/`readlink -f` — so a relative path, a `../` round-trip, or a symlink alias cannot dodge the record-edit deny). For **Bash it is post-hoc only for arbitrary side effects**: there is no single reliable target to pre-check, so a Bash-caused violation is caught on the *next* gate call (the diff vs base already shows it), not before the command runs — do not read this as pre-hoc-blocking arbitrary Bash side effects. The hook additionally does a narrow, **BEST-EFFORT** pre-hoc pattern-match on the Bash command text for the record's own filename or the literal `autonomy-run` marker and denies a match — this raises the bar, it does NOT close the general Bash-record-write vector (indirection via variables, python/base64, heredocs, or other unrecognized shell constructions still evades it; that residual is a deferred operator decision, not solved). The run record itself is not agent-editable while a run is active — the hook denies any edit targeting it. Inert when `CLAUDE_SUBTEAMS_AUTONOMY` is unset.
- **`scripts/autonomy-check.sh` = checkpoint evidence**, not prevention — it evaluates scope/caps and, via `scripts/autonomy-check.sh --checkpoint`, appends the script-authored `AUTONOMY_CHECKPOINT:` audit line (nothing derives caps from it — caps are total-run, cumulative from the base commit, recomputed fresh from git every call).
- **Prose = behavioral protocol** (re-hydration, kill-switch, self-assessed risk-triggers): posture, not structure. Do not mistake it for a gate.

**Verifiability precondition.** A task with no external verifier — a deterministic exit code (tests/lint) or, for high-stakes runs, the rare Codex adversary anchored to the written criteria — is **not eligible** for autonomy. Run it interactively.

**Checkpoint.** Every milestone in autonomy is a **non-blocking evidence checkpoint**: run `scripts/autonomy-check.sh --checkpoint` (≥1 deterministic exit code), which records the script-authored audit line, and **continue unless a blocker class fires**. The exit code is the gate, not your judgment.

**Failure classes:**

| Class | Trigger | Action |
|-------|---------|--------|
| operator-decision-required (STRUCTURAL) | cap-exceeded OR out-of-scope path — caught by the hook before the edit for file-writing tools; at the next checkpoint for Bash side effects | STOP; hand to operator |
| external-evidence-required | a material claim needs a verifier not yet run | run it; if impossible, STOP |
| reviewer-disagreement | **END-OF-RUN only** — no mid-run reviewer dispatch | surface at run end |
| local-fixable | error the run can resolve itself, with evidence | fix, re-verify, continue |
| informational | note, no decision | log, continue |

**Kill-switch & re-hydration (behavioral protocol).** Any operator message mid-run = an immediate operator-decision-required checkpoint at the next tool boundary. On any compaction / context loss, re-read the contract + rails before the next action; if the grant+scope record is not recoverable verbatim, revert to interactive.

**Env / caps.** `CLAUDE_SUBTEAMS_AUTONOMY` (gate on/off) · total-run, cumulative-from-base `CLAUDE_SUBTEAMS_AUTONOMY_MAX_FILES/LINES` (default 10/400). Grant expiry is the wall-clock bound.

*Split-trigger: if this file exceeds 200 lines or this section exceeds 40% of it, extract Autonomy Mode into a dedicated `autonomous-execution` skill (Tier 3).*

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
- (Interactive mode) Proceed past a milestone without user acknowledgment. In an autonomy run the milestone is instead a non-blocking evidence checkpoint (see `## Autonomy Mode`) — you continue unless a blocker class fires.

**ALWAYS:**
- Build dependency graph before executing
- Use git worktrees for parallel isolation
- Run compilation + review + tests after every task
- Escalate to user after 3 gate failures
- Checkpoint at every milestone — interactively: summarize + ask + wait; in an autonomy run: the evidence checkpoint (deterministic exit code + script-authored record). Never skip the checkpoint in either mode.

## Integration

**Required workflow skills:**
- **claude-subteams:using-git-worktrees** - Recommended for Full pipeline and parallel work. For Standard pipeline, a feature branch is sufficient.
- **claude-subteams:writing-plans** - Creates the plan this skill executes
- **claude-subteams:finishing-branch** - Complete development after all tasks
