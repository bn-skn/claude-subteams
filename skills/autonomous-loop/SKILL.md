---
name: autonomous-loop
description: Use ONLY when the operator explicitly requests loop-mode in the current message AND a fresh autonomy run record exists — drives an in-session prompt→act→verify→continue cycle over an active IMPL-PLAN. Never ambient, never self-activated. NOT for a bare "continue" / "keep going" / "продолжай" without an active autonomy grant.
---

# Autonomous Loop

## Overview

An in-session cycle that walks an active IMPL-PLAN item by item — take the next open item, run it through the pipeline, prove it with a mechanical checker, mark it, continue — without a human pause between items. It is the loop `executing-plans` `## Autonomy Mode` lacks: same grant machinery, same caps, same hook enforcement, plus the outer "next item" step.

**Announce at start:** "I'm using the autonomous-loop skill to work this plan under the active autonomy grant."

**This skill adds NO new permissions.** It reuses the autonomy contract, `autonomy-gate` hook, and `autonomy-check.sh` checkpoints verbatim. If any of those is absent or stale, you are not in a loop — you are interactive.

## Activation Contract (both required, no exceptions)

A loop runs only when BOTH hold, checked against real state, not memory:

1. **Explicit loop request in the CURRENT operator message** — "work the plan autonomously", "loop through it", or equivalent. A grant from an earlier turn does not re-arm the loop.
2. **A fresh autonomy run record** in the active contract (`living-plan` §3a: grant, criteria snapshot, scope globs, base commit, session id, expiry, caps). Same record `executing-plans` `## Autonomy Mode` requires. No record / expired / session mismatch → **do not loop**: run interactively, ask and wait.

Missing one → announce which, then fall back precisely: **no loop request but a valid run record** → autonomy per `executing-plans` WITHOUT the outer loop (the grant is alive — don't waste it by dropping to interactive); **no valid record** → interactive flow, ask and wait. Never improvise a grant.

## The Cycle

Repeat while the grant is alive and open items remain:

1. **Select** the first item marked `[ ]` in the active IMPL-PLAN (`docs/plans/active/IMPL-PLAN-*.md`).
2. **Execute** it through the pipeline matching its scope (using-subteams §6). Non-negotiable review floor:
   - Any logic change → **code-reviewer** (mandatory).
   - Security-sensitive or breaking-change item → the **full critic set** — code-reviewer + architecture-guard + devils-advocate, plus **GPT cross-review when Codex is available** (`cross-review` skill; Codex down → Claude-only, never block).
   - Spawn reviewers per the reviewer-name rule (using-subteams §2, `cross-review`): no custom name, or a name containing `code-reviewer`, so the review-gate marker resolves.
3. **Checkpoint (mechanical, real output only)** — run all of, and read their actual output:
   - project typecheck / build (e.g. `tsc --noEmit`) and the project test command;
   - `scripts/check-plan.sh` (plan integrity + status rollup);
   - `scripts/autonomy-check.sh --checkpoint` (scope/caps + script-authored `AUTONOMY_CHECKPOINT:` audit line).
   The deterministic exit codes are the gate, not your judgment. A checkpoint you cannot show output for did not happen.
4. **Branch on the result:**
   - **Green** (all exit 0, no critical/high review finding open) → flip the item to `[x]`, update the Rollup, go to the next item.
   - **Red** → **one** fix attempt (re-dispatch with the failure evidence), then re-run the checkpoint. Second red on the same item → **blocker-checkpoint**: stop the loop, classify per the `executing-plans` `## Autonomy Mode` failure table, hand to the operator. (Two strikes here vs executing-plans' interactive three — deliberate: an unattended run earns a stricter fuse.)

## Plan Rewriting (living-plan bounds)

Living-plan evolution is allowed inside the loop — but the write-once line holds:

- **Agent-owned, free to change:** add items, split an item into finer items, progress markers, Rollup, checkpoint evidence.
- **Operator-owned, loop-STOPPING:** acceptance criteria are immutable after approval. A needed change is an append-only `REVISED: <what> — <why> — "<operator ack quote>"` — which requires an operator ack, which means **the loop stops and escalates**. You cannot self-approve a criteria change and keep looping.

## Stop Conditions

Halt the cycle immediately on any of:

- **Plan closed** — no `[ ]` items remain.
- **Blocker** — a second red on one item, or any `executing-plans` blocker class (operator-decision-required, external-evidence-required).
- **Grant exhausted or expired** — caps hit (the `autonomy-gate` hook blocks the offending edit structurally) or wall-clock expiry passed.
- **Kill-switch — ANY operator message.** A message mid-loop is an immediate stop at the next tool boundary (same rule as `executing-plans`). If you were mid-item, report state and wait; do not push through.

## Continuation Is Behavioral, Not Hooked

Continuation is a **posture**: "while the grant is alive and open items remain, do not end the turn — select the next item and keep going." There is **no Stop-hook nudge** and none is to be added (operator decision 13.07, plan header of `docs/plans/2026-07-13-subteams-1.32-research.md` — supersedes P8 rule 4's conditional allowance: a Stop-hook that re-injects context risks eating the operator's answer and provoking unwanted work). The loop lives entirely in your own control flow, bounded by the stop conditions above.

## Re-hydration

On any compaction or context loss mid-loop: re-read the contract + run record + rails before the next action. If the grant/scope record is not recoverable verbatim, **revert to interactive** — do not resume the loop from a remembered grant.

## Final Report

When the loop halts (for any reason), report:

1. **Item table** — each plan item touched, final status (`[x]` / `[ ]` / blocked), and why it stopped where it did.
2. **Checkpoint evidence** — the `AUTONOMY_CHECKPOINT:` lines and the checker exit codes per item (real output, not "passed").
3. **Plan rewrites** — every item added or split, and any escalated `REVISED:` criteria request.
4. **Halt reason** — which stop condition fired.

## Integration

- **claude-subteams:executing-plans** — `## Autonomy Mode` owns the grant/hook/checkpoint mechanics; this skill only adds the outer loop. When they seem to conflict, executing-plans wins **on grant/checkpoint mechanics only** — the review floor (using-subteams §0 rule 2: any logic change → code-reviewer) is not mechanics and always holds; its "END-OF-RUN" row defers *resolving reviewer disagreements*, never the reviews themselves.
- **claude-subteams:living-plan** — §3a run record schema, write-once criteria, Rollup.
- **claude-subteams:cross-review** — critic set and Codex availability rules for security/breaking items.
- **claude-subteams:using-subteams** — §6 pipeline scoping, §2 reviewer-name rule.
