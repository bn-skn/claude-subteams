---
name: living-plan
description: "The single plan-of-record every actor reads and writes, in two weights: a light contract (scope / acceptance criteria / non-goals) for risk-triggered or multi-session single-feature work, or a full package → criterion → status → blocker matrix for multi-package / contracted work. Write-once acceptance criteria; kept fresh as work closes."
---

# Living Plan-of-Record

## 1. When to Use This Skill

The plan-of-record comes in **two weights**. Write the one the work earns — never more.

- **Light contract** (one screen: **scope / acceptance criteria / non-goals**): for **risk-triggered** work (using-subteams §6) OR any single feature that spans **multiple sessions**. It is the smallest durable artifact that answers "am I still on scope?" when the operator is not watching.
- **Full matrix** (packages + Rollup, §2 below): only for **genuine multi-package work** (≥2 deliverables) OR a **TZ / requirements doc with acceptance clauses**.

**Tiebreak:** a risk-trigger mandates *writing* the artifact; it does **not** escalate pipeline depth. Process depth is set by the pipeline tier, independently — a light contract on a Standard task keeps it Standard.

Worked examples:
- One-line auth fix (security boundary) → **light contract**; pipeline stays Standard.
- 8-file mechanical rename, no logic, no risk-trigger → **no artifact**.
- Multi-session single feature → **light contract**.
- Contracted TZ with acceptance clauses → **full matrix**.

**Default when unsure:** check the risk-triggers. If any fires, write at least a light contract; volume alone never mandates one. Trivial, zero-risk, single-session work gets nothing — a plan-of-record there is bureaucracy.

The problem this solves: without a written contract, "how close are we to acceptance?" is invisible — scattered across the estimate, `BACKLOG.md`, and `docs/specs/*`. The artifact is the single place that answers it at a glance, and the only safety net once the operator steps out of the loop.

## 2. The Artifact

One file per contract/project: `docs/plans/active/IMPL-PLAN-<slug>.md`. It is a **matrix that rolls up**, not a flat checklist. Start from `templates/IMPL-PLAN.md`.

Structure (see the template for the exact form):

- A **sentinel** line (`> STATUS: TEMPLATE — not yet populated`) that MUST be removed once real content is filled in.
- A **Rollup** table: one row per package with counts of acceptance criteria by status (DONE / WIP / TODO / BLOCKED) and an Acceptance column.
- Per-package sections (`## P<n> — <name>`), each mapping to TZ sections, each listing acceptance criteria as checkboxes with an explicit status token and (when applicable) a blocker and owner.

Status tokens (use exactly these): `DONE`, `WIP`, `TODO`, `BLOCKED`, written as a **trailing marker after a separator** (e.g. `— DONE`, `— TODO — blocker: …`). A checkbox `- [x]` is DONE; `- [ ]` is anything not-done — the trailing token disambiguates WIP/TODO/BLOCKED. An unresolved acceptance criterion is marked `**TBD — unresolved**` (the validator accepts `TBD` as a recognized marker).

## 3. Lifecycle

1. **Author** (during `writing-plans`, for qualifying work): generate `IMPL-PLAN-<slug>.md` from the estimate + TZ, in-context. Remove the sentinel. Mark every criterion `TODO`. Map each package to its TZ section. **Never invent acceptance criteria** — if a package's acceptance is unclear, mark it `**TBD — unresolved**` and ask, exactly as the architecture-capture flow does for ADRs.
2. **Write-once acceptance criteria:** once the operator approves the plan, the **original acceptance criteria are immutable** — never rewrite them. Any change lands ONLY as an appended line:
   `REVISED: <what changed> — <why> — "<operator-ack quote>"`
   The operator-ack quote (a verbatim snippet of the operator's approving message) is **REQUIRED** whenever scope or acceptance changes; a `REVISED:` line that alters scope/acceptance without it fails `check-plan.sh`. This is the anti-goalpost-drift anchor: "am I on scope?" is always answered against the original criteria + explicit `REVISED:` lines, never a silently edited doc.
3. **Update** (during `executing-plans`, as each task closes): flip the matching criterion's status token and checkbox; recompute the affected package's Rollup row.
4. **Refresh** (doc-freshness): a change that closes a tracked package/backlog item must also update the matching plan-of-record criterion — keeping the plan in lockstep with `INDEX.md` / `CHANGELOG.md` / `BACKLOG.md`. The `session-end-reminder` hook reminds when the plan lags.
5. **Close**: when all packages are accepted, move the file `active/ → completed/` (existing convention).

## 3a. Autonomy Run Record (autonomy runs only)

When — and only when — an autonomy run is granted, the active plan carries a machine-readable **run record**, delimited by HTML-comment markers so `grep`/`awk` can extract it without parsing prose. **One key per line — no packed multi-key lines, no trailing inline comments.** The parser is prefix-anchored on the first `KEY: ` per line with no normalizer: a packed or malformed line fails closed (cannot evaluate) rather than being silently parsed, and free-text fields (`AUTONOMY_GRANT`, `AUTONOMY_CRITERIA_SNAPSHOT`) can never forge a later key by embedding it on the same line.

    <!-- autonomy-run:begin -->
    AUTONOMY_GRANT: <verbatim operator grant, one line>
    AUTONOMY_CRITERIA_SNAPSHOT: <immutable copy of the acceptance criteria at grant, one per line — anti-goalpost-drift snapshot>
    AUTONOMY_SCOPE: <comma-separated path globs>
    AUTONOMY_BASE_COMMIT: <sha at grant>
    AUTONOMY_SESSION: <session id>
    AUTONOMY_GRANTED_EPOCH: <unix>
    AUTONOMY_EXPIRES_EPOCH: <unix — max TTL; expiry IS the wall-clock bound>
    AUTONOMY_MAX_FILES: <n>
    AUTONOMY_MAX_LINES: <n>
    AUTONOMY_CHECKPOINT: <appended by scripts/autonomy-check.sh itself — never by the agent>
    <!-- autonomy-run:end -->

**Scope semantics:** globs are bash case-patterns — `*` crosses `/`, so `src/*` covers the whole subtree. The record file itself is auto-exempt from scope (and excluded from the files cap). A cap that is present but non-numeric fails closed (cannot evaluate), never "unbounded". `AUTONOMY_MAX_FILES`/`AUTONOMY_MAX_LINES` are **total-run caps, cumulative from `AUTONOMY_BASE_COMMIT`** — recomputed fresh from git on every check, not a running counter.

**Ownership:** grant, criteria snapshot, scope, expiry, and caps are **operator-owned** — the agent copies them in verbatim at grant and never edits them mid-run. **The record file itself is not agent-editable while a run is active** — `hooks/autonomy-gate` denies any Edit/Write/MultiEdit/NotebookEdit targeting it, structurally, not just by convention (target paths are canonicalized before comparison, closing relative/`../`/symlink-alias bypasses). For **Bash**, the same protection is only **best-effort**: the hook pattern-matches the command text for the record's filename or the literal `autonomy-run` marker and denies a match, but this is a string match, not sandboxing — it does not catch indirection via variables, python/base64, or other unrecognized shell constructions. The `AUTONOMY_CHECKPOINT:` lines are **script-authored, audit-only evidence**: `scripts/autonomy-check.sh` appends them via `--checkpoint`, closing the self-graded-counter hole — the agent cannot write its own progress evidence, and nothing in the script derives caps from prior checkpoint lines. Absent a fresh record, execution is interactive. Full activation contract and enforcement layers live in `executing-plans` (`## Autonomy Mode`).

## 4. Validation

Run `scripts/check-plan.sh <project-dir>` before declaring plan-of-record work done. It checks every `docs/plans/active/IMPL-PLAN-*.md` for: sentinel removed, a Rollup table present, and every checklist item carrying a recognized status marker (`— DONE/WIP/TODO/BLOCKED` or `TBD`). Exit 0 = valid (or no plan-of-record present); exit 1 = a problem, printed. It is mechanical evidence, not self-attestation — paste its output as proof, do not claim freshness from memory.

## 5. Relationship to Other Skills

- `writing-plans` — authors the plan-of-record for qualifying work; for everything else, a brief plan there is enough.
- `executing-plans` — flips criterion status as tasks close.
- `doc-quality-gate` / `session-end-reminder` hook — the plan-of-record is a tracked artifact alongside `INDEX.md` / `CHANGELOG.md` / `BACKLOG.md`; keep it fresh as items close.
- `adr-tracker` / `decision-context` — same in-context-authorship discipline: never fabricate; mark gaps `**TBD — unresolved**`.

## 6. Critical Rules

1. **Weight gate:** write a **light contract** when any risk-trigger fires (using-subteams §6) or a single feature spans multiple sessions; reserve the **full matrix** for multi-package (≥2) or TZ-with-acceptance work. A risk-trigger mandates the artifact, not a deeper pipeline. Impose **nothing** on trivial, zero-risk, single-session tasks.
2. **Never fabricate acceptance criteria.** Unknown acceptance → `**TBD — unresolved**`, then ask. Authored in-context by the orchestrator, never reconstructed by a fresh-context subagent.
3. **Rollup must stay consistent** with the per-package criteria — a Rollup row that disagrees with its section is worse than no rollup.
4. **One source of truth.** Until multi-instance coordination lands, the markdown file IS the truth; the validator guards its integrity. (When concurrent agents edit it, the ledger moves into the coordination substrate and the markdown is rendered — see the multi-instance spec.)
5. **Remove the sentinel** the moment real content is filled in; a populated plan that still carries the template sentinel fails the validator.
