---
name: living-plan
description: "Maintains a single multi-level plan-of-record (package → section → acceptance criterion → status → blocker) with checkboxes, kept fresh as work closes. For multi-package / contracted work only."
---

# Living Plan-of-Record

## 1. When to Use This Skill

Use this skill **only for multi-package or contracted work** — that is, when EITHER holds:

1. The work decomposes into **≥2 packages** (e.g. a paid estimate split into deliverables), OR
2. There is an explicit **TZ / requirements doc with acceptance clauses** the work is measured against.

For single-feature or ad-hoc work, use `writing-plans` (a brief plan) instead — a plan-of-record there is bureaucracy. When unsure whether the work qualifies, it probably does not.

The problem this solves: on contracted work the real plan is scattered across the estimate (packages), `BACKLOG.md` (status), and `docs/specs/*` (per-feature specs), so "how close are we to acceptance?" is invisible. The plan-of-record is the single matrix that answers it at a glance.

## 2. The Artifact

One file per contract/project: `docs/plans/active/IMPL-PLAN-<slug>.md`. It is a **matrix that rolls up**, not a flat checklist. Start from `templates/IMPL-PLAN.md`.

Structure (see the template for the exact form):

- A **sentinel** line (`> STATUS: TEMPLATE — not yet populated`) that MUST be removed once real content is filled in.
- A **Rollup** table: one row per package with counts of acceptance criteria by status (DONE / WIP / TODO / BLOCKED) and an Acceptance column.
- Per-package sections (`## P<n> — <name>`), each mapping to TZ sections, each listing acceptance criteria as checkboxes with an explicit status token and (when applicable) a blocker and owner.

Status tokens (use exactly these): `DONE`, `WIP`, `TODO`, `BLOCKED`. A checkbox `- [x]` is DONE; `- [ ]` is anything not-done — the trailing token disambiguates WIP/TODO/BLOCKED.

## 3. Lifecycle

1. **Author** (during `writing-plans`, for qualifying work): generate `IMPL-PLAN-<slug>.md` from the estimate + TZ, in-context. Remove the sentinel. Mark every criterion `TODO`. Map each package to its TZ section. **Never invent acceptance criteria** — if a package's acceptance is unclear, mark it `**TBD — unresolved**` and ask, exactly as the architecture-capture flow does for ADRs.
2. **Update** (during `executing-plans`, as each task closes): flip the matching criterion's status token and checkbox; recompute the affected package's Rollup row.
3. **Refresh** (doc-freshness): a change that closes a tracked package/backlog item must also update the matching plan-of-record criterion — keeping the plan in lockstep with `INDEX.md` / `CHANGELOG.md` / `BACKLOG.md`. The `session-end-reminder` hook reminds when the plan lags.
4. **Close**: when all packages are accepted, move the file `active/ → completed/` (existing convention).

## 4. Validation

Run `scripts/check-plan.sh <project-dir>` before declaring plan-of-record work done. It checks every `docs/plans/active/IMPL-PLAN-*.md` for: sentinel removed, a Rollup table present, every checklist item carrying a recognized status token, and no orphan blocker text. Exit 0 = valid (or no plan-of-record present); exit 1 = a problem, printed. It is mechanical evidence, not self-attestation — paste its output as proof, do not claim freshness from memory.

## 5. Relationship to Other Skills

- `writing-plans` — authors the plan-of-record for qualifying work; for everything else, a brief plan there is enough.
- `executing-plans` — flips criterion status as tasks close.
- `doc-quality-gate` / `session-end-reminder` hook — the plan-of-record is a tracked artifact alongside `INDEX.md` / `CHANGELOG.md` / `BACKLOG.md`; keep it fresh as items close.
- `adr-tracker` / `decision-context` — same in-context-authorship discipline: never fabricate; mark gaps `**TBD — unresolved**`.

## 6. Critical Rules

1. **Scope gate:** use this skill ONLY for multi-package (≥2) or TZ-with-acceptance work. Do NOT impose a plan-of-record on single-feature tasks.
2. **Never fabricate acceptance criteria.** Unknown acceptance → `**TBD — unresolved**`, then ask. Authored in-context by the orchestrator, never reconstructed by a fresh-context subagent.
3. **Rollup must stay consistent** with the per-package criteria — a Rollup row that disagrees with its section is worse than no rollup.
4. **One source of truth.** Until multi-instance coordination lands, the markdown file IS the truth; the validator guards its integrity. (When concurrent agents edit it, the ledger moves into the coordination substrate and the markdown is rendered — see the multi-instance spec.)
5. **Remove the sentinel** the moment real content is filled in; a populated plan that still carries the template sentinel fails the validator.
