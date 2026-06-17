# Living Plan-of-Record Ledger — Design Specification

**Date:** 2026-06-17
**Status:** Draft — for approval (not yet implemented)
**Author:** Bogdan + Claude Opus 4.8
**Idea ref:** Idea 2 of the 3-idea modernization set (paired with Idea 1 doc-freshness-triad and Idea 3 multi-instance-coordination)
**Research:** synthesized from deep-research run wf_c8320ebf-110 (42 agents: living-spec / shared-task-ledger patterns — Augment Code, MindStudio, Claude Code agent-teams)

---

## 1. Problem

The real "plan of record" for a contracted project is scattered across three unlinked artifacts:

- the **estimate / scope** (decomposition into paid packages),
- `docs/BACKLOG.md` (live status), and
- `docs/specs/*` (per-feature specs).

`docs/plans/active/` sits empty. To answer "what is left until acceptance?" a human has to hold three documents in their head at once and reconcile them manually. When work is structured by a paid contract (N packages ↔ a TZ with acceptance clauses §12), readiness-to-deliver is not visible at a glance.

This is the structural twin of Idea 1: Idea 1 keeps the *cross-cutting trackers* fresh; Idea 2 *synthesizes them into one acceptance-oriented plan*. Both are about the connective tissue between otherwise-disconnected docs.

## 2. Vision

A **single, multi-level, self-updating plan-of-record** with checkboxes, generated and maintained as a first-class artifact — in the spirit of the old `IMPL-PLAN-v2.md`, but living rather than hand-curated and stale.

The plan is a **matrix**, not a flat list:

```
Package → TZ section → Acceptance criterion → Status (DONE/WIP/TODO/BLOCKED) → Blocker/Owner
```

Each level rolls up: a package is DONE only when all its acceptance criteria are DONE. One glance answers "how close to delivery."

## 3. Scope

**In scope:**
- A reusable mechanism (skill + template + optional generator/validator script) that produces and maintains `docs/plans/active/IMPL-PLAN-*.md`.
- A defined multi-level schema (package / section / criterion / status / blocker / owner).
- Integration points: `writing-plans` (author the plan-of-record from estimate + TZ), `executing-plans` (update status as tasks complete), and the Idea 1 doc-freshness hook (keep the plan fresh alongside INDEX/CHANGELOG/BACKLOG).
- Generic across projects — NOT hard-wired to claudebot.

**Out of scope (this spec):**
- Multi-instance concurrent editing of the ledger — that is Idea 3's substrate. This spec assumes a single writer (one Claude Code session). If multi-instance lands, the ledger source-of-truth moves into Idea 3's coordination layer and the markdown is rendered from it (see §7).
- Automatic parsing of arbitrary estimate/TZ formats. The orchestrator populates the plan in-context from whatever estimate/TZ exists (same model as the architecture-capture pipeline: orchestrator is the in-context author, a script provides mechanical evidence).

## 4. Design

### 4.1 Source-of-truth model

Two representations, one direction of truth:

- **Human representation (primary for single-instance):** `docs/plans/active/IMPL-PLAN-<slug>.md` — markdown with nested checkboxes and a rollup table. Human-readable, diff-friendly, matches the plugin's all-markdown ethos.
- **Machine validation:** a `check-plan.sh`-style script that verifies structural integrity (every criterion has a status, rollups are consistent, no orphan blockers) and prints what is stale — evidence, not self-attestation. Mirrors `check-arch-docs.sh` from the architecture-capture pipeline (v1.18.0).

Rationale: research (Augment "living Spec", MindStudio shared task list, Claude Code agent-teams 3-state list) converges on a **markdown ledger with explicit status fields** as the established pattern for single-orchestrator coordination. Markdown stays the source of truth until concurrency forces a structured backend (Idea 3).

### 4.2 Schema (markdown)

```markdown
# IMPL-PLAN: <project/contract name>

> STATUS: TEMPLATE — not yet populated   (sentinel, removed once real)
> Source: <estimate ref> + <TZ ref>   Last synced: <date>

## Rollup
| Package | Criteria | DONE | WIP | TODO | BLOCKED | Acceptance |
|---------|---------:|-----:|----:|-----:|--------:|-----------|
| P1 ...  |   5      |  5   |  0  |  0   |   0     | ✅ accepted |

## P1 — <package name>  (maps to estimate item, ₽ optional)
- TZ §<n> — <section title>
  - [x] AC-1: <acceptance criterion> — DONE (<commit/PR>)
  - [ ] AC-2: <criterion> — WIP — blocker: <text> — owner: <agent/human>
```

### 4.3 Lifecycle

1. **Author** (`writing-plans`): on a contract/multi-package task, the orchestrator generates `IMPL-PLAN-<slug>.md` from the estimate + TZ, in-context. Unknown items marked `**TBD — unresolved**`, never invented (same discipline as ADR capture).
2. **Update** (`executing-plans`): when a task closes, its acceptance criterion flips status; rollup recomputed.
3. **Refresh** (Idea 1 hook): the doc-freshness gate is extended — a change that closes a backlog/package item must also update the matching plan-of-record criterion. The hook reminds when `IMPL-PLAN` is stale relative to a closed task.
4. **Close**: when all packages accepted, plan moves `active/ → completed/` (existing convention).

### 4.4 New skill

`living-plan` (a.k.a. `plan-of-record`) under `skills/process/`: defines the schema, the author/update/refresh lifecycle, and the rollup discipline. Referenced from `writing-plans` and `executing-plans` rather than duplicating them.

## 5. Key decisions — RESOLVED (2026-06-17, owner approval)

1. **Storage:** ✅ **markdown-primary + validation script.** Revisit a structured backend only when Idea 3 (multi-instance) lands.
2. **New skill vs extend existing:** dedicated `living-plan` skill (single job, discoverable). *(recommendation stands; confirm at impl.)*
3. **Hook coupling:** ✅ **extend the Idea 1 doc-freshness gate** to include `IMPL-PLAN` — same connective-tissue job. (Implementation order means Idea 1 ships first, Idea 2 plugs its refresh step into that gate.)
4. **Scope trigger:** ✅ **mandatory only for multi-package / contracted work** (≥2 packages OR an explicit TZ with acceptance clauses). Single-feature work keeps plain `writing-plans`. No bureaucracy on small tasks.

## 6. Open questions

- Should the rollup support **percentage / weighted** progress (criteria weighted by estimate ₽), or pure counts? (Counts simpler; weights more honest for delivery-readiness.)
- Does the plan-of-record **replace** `BACKLOG.md` for contracted projects, or sit beside it? (Proposal: beside — BACKLOG is the idea/triage funnel, IMPL-PLAN is the acceptance matrix.)

## 7. Relationship to other ideas

- **Idea 1 (doc-freshness triad):** Idea 2 adds `IMPL-PLAN` as a fourth tracked artifact in the freshness gate. Implement Idea 1 first; Idea 2's refresh step plugs into it.
- **Idea 3 (multi-instance):** if multiple instances edit the plan concurrently, markdown-as-truth breaks (concurrent edits conflict). Then the ledger moves into Idea 3's coordination substrate (file-locked or SQLite-backed) and the markdown is *rendered* from it, not hand-edited. This spec's schema is designed to survive that migration (the matrix maps cleanly onto a table/rows).

## 8. Risks & nuances

- **Staleness is the whole enemy:** a plan-of-record that drifts is worse than none (false confidence). The validation script + hook coupling are the defense; without them this degrades to another manual artifact.
- **Over-application:** forcing the matrix onto single-feature work is bureaucracy. Scope trigger (§5.4) must be enforced.
- **In-context authorship:** like architecture-capture, the orchestrator must author from real estimate/TZ, never fabricate acceptance criteria. `**TBD — unresolved**` is mandatory for gaps.
