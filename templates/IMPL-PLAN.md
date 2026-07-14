# IMPL-PLAN: <PROJECT_OR_CONTRACT_NAME>

> STATUS: TEMPLATE — not yet populated
> Source: <estimate ref> + <TZ ref>   ·   Last synced: <YYYY-MM-DD>

<!--
  Living plan-of-record. One file per contract/project, under docs/plans/active/.
  Two weights (see the living-plan skill): a LIGHT CONTRACT (scope / acceptance criteria / non-goals)
  for risk-triggered or multi-session single-feature work, or this FULL MATRIX (packages + Rollup) for
  multi-package (>=2) or TZ-with-acceptance work. A risk-trigger mandates writing the artifact, not a deeper pipeline.
  Status tokens (use exactly): DONE | WIP | TODO | BLOCKED — as a trailing marker
  after a separator, e.g. "— DONE". An unresolved criterion uses **TBD — unresolved**
  (also accepted by the validator). Never invent acceptance criteria — mark unknowns TBD and ask.
  Remove the STATUS sentinel line above once real content is filled in.
-->

<!--
  Write-once acceptance criteria: after operator approval the ORIGINAL criteria are immutable.
  Changes append only, never rewrite:  REVISED: <what> — <why> — "<operator-ack quote>"
  The ack quote is REQUIRED when scope/acceptance changes (else check-plan.sh fails).
  Operator-owned: acceptance criteria, autonomy grant / scope / caps.  Agent-owned: progress, Rollup, checkpoints.
  Autonomy runs only: a run record lives between the autonomy-run:begin / autonomy-run:end HTML-comment markers,
  ONE KEY PER LINE (no packed multi-key lines, no trailing inline comments — a malformed line fails closed,
  never gets silently parsed). AUTONOMY_CHECKPOINT: lines are audit-only evidence appended by
  scripts/autonomy-check.sh, never by the agent, and are not editable by the agent while the run is
  active (hooks/autonomy-gate denies edits to this file during a run). Schema: living-plan skill (§3a).
-->

## Rollup

| Package | Criteria | DONE | WIP | TODO | BLOCKED | Acceptance |
|---------|---------:|-----:|----:|-----:|--------:|-----------|
| P1 — <name> | 0 | 0 | 0 | 0 | 0 | <pending/accepted> |

## P1 — <package name>   (estimate item; ₽ optional)

- TZ §<n> — <section title>
  - [ ] AC-1: <acceptance criterion> — TODO
  - [ ] AC-2: <acceptance criterion> — TODO — blocker: <text> — owner: <agent/human>

<!-- Repeat per package. A package is DONE only when all its acceptance criteria are DONE. -->

<!--
  OPTIONAL SECTIONS — risk-triggered, NOT default ceremony (see the writing-plans skill).
  Include a section ONLY when its trigger fires; delete the ones that do not apply.
  Not user-facing + no schema change + no API change → include NONE of these.

  ## User Stories            (trigger: user-facing feature)
  - As <role>, I want <action>, so that <value>.
    - Acceptance: <observable criterion>
  (The ui-tester reads these as scenarios in scenario mode — keep them concrete.)

  ## Data Design             (trigger: database schema change — see database-design skill)
  - Tables/fields: <changes>
  - Indexes: <added/removed>
  - Migration: forward <...> · rollback <...>

  ## Interface Contract      (trigger: new/changed public API — see api-design skill)
  - Contract source of truth: docs/openapi.yaml (link the endpoints; do not restate inline)
  - Changes: <endpoints / shapes added or altered>
-->
