# Architecture Capture Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: claude-subteams:subagent-driven-dev. This is agentic/prompt work — Section 6.5 applies (prompt-engineer authors, prompt-evaluator validates).

**Goal:** Close the gap where architecture decisions made during brainstorming never land in `ARCHITECTURE.md`/`CONVENTIONS.md` — by capturing decisions as ADRs during the interview, projecting them into the docs (orchestrator in-context), and gating structural implementation on populated docs via a mechanical check. NO new agent.

**Architecture:** Capture → projection → mechanical gate → validation, wired from EXISTING pieces (`adr-tracker`, `decision-context`, `doc-agent`, the `Full + Architecture` pipeline row, `verification-gate`). The orchestrator stays the in-context author (it holds the interview); a check script provides evidence, not self-attestation.

**Tech Stack:** Markdown skills + bash check script. No TS.

**Why no agent:** Two adversaries (Claude `devils-advocate` + cross-model `gpt-devils-advocate`) converged: a fresh-context author reconstructs decisions from a lossy brief = "authoritative-looking fiction"; and `ARCHITECTURE.md`/`CONVENTIONS.md` are load-bearing state read by `architecture-guard` as truth, so wrong docs poison the validator. Fix is capture semantics + mechanical gate, not labor.

---

## Shared Contract (both authors MUST honor these exact strings)

- **Check script:** `scripts/check-arch-docs.sh <project-dir>` — exit 0 = docs populated; exit 1 = stub markers found. Scans `<dir>/docs/ARCHITECTURE.md` and `<dir>/docs/CONVENTIONS.md`. Prints which markers/files failed.
- **Stub markers (any present → not populated):** the sentinel line `> STATUS: TEMPLATE — not yet populated`, plus `<PLACEHOLDER`, `<STACK>`, `<FRAMEWORKS>`, `<PROJECT_NAME>`, `<DATABASE>`, `ComponentName`, and HTML-comment placeholders `<!--` that remain in required sections.
- **ADR linkage:** `ARCHITECTURE.md` carries a `## Decision Records` section listing accepted ADRs as `- [ADR-NNN: Title](adr/NNN-title.md)`. Each non-obvious architectural choice in the doc traces to an ADR or is explicitly marked `**TBD — unresolved**` (never invented).
- **Scope of the gate:** greenfield (new project) + non-trivial structural changes (new module, layer/dependency-direction change, new external integration). NOT every Full-pipeline task, NOT logic-only features.
- **Version:** bump to **1.18.0** (plugin.json, marketplace.json plugin entry, using-subteams skill version 1.7.0 → 1.8.0).

## Task A — Mechanical artifact + templates + version (developer, sonnet)

**Files:**
- Create: `scripts/check-arch-docs.sh`
- Modify: `templates/ARCHITECTURE.md`, `templates/CONVENTIONS.md`
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (version → 1.18.0)

1. Write `check-arch-docs.sh`: bash, takes `$1` = project dir (default `.`). For each of `docs/ARCHITECTURE.md`, `docs/CONVENTIONS.md`: if file missing → fail; grep for any stub marker (contract list) → fail and print marker+file. Exit 1 if any failure, 0 if both clean. Must pass `bash -n` and run under `set -euo pipefail`-safe logic (handle missing files without crashing).
2. Templates: add the sentinel line `> STATUS: TEMPLATE — not yet populated` near the top of both, and a `## Decision Records` section to `ARCHITECTURE.md` (placeholder list referencing `adr/`). Keep existing structure.
3. Version bumps to 1.18.0 in both plugin manifests.

## Task B — Skill prose + docs (prompt-engineer, opus)

**Files:**
- Modify: `skills/brainstorming/SKILL.md`, `skills/using-subteams/SKILL.md`, `skills/project-scaffold/SKILL.md`, `skills/verification-gate/SKILL.md`
- Modify: `CHANGELOG.md`, `README.md`, `llms-install.md` (roster/pipeline notes if architecture flow is described)
- Modify: `hooks/user-prompt-check` (add greenfield/structural → architecture-capture advisory line)

1. **brainstorming**: in the design/after-design flow, add greenfield+structural branch — capture each accepted arch decision as an ADR (`adr-tracker`) + decision-context block DURING the interview; then orchestrator (in-context) populates `docs/ARCHITECTURE.md` + `docs/CONVENTIONS.md` from those records with ADR provenance links; unresolved items marked `**TBD — unresolved**`, never invented. Tie to existing step 7 (Write design doc).
2. **using-subteams**: extend the `Full + Architecture` row; add an explicit gate step — structural/greenfield work does not enter IMPLEMENT until `check-arch-docs.sh` passes and decisions trace to ADRs. New Critical Rule 24, scoped per contract. Bump skill version to 1.8.0.
3. **project-scaffold**: Step 4 handoff — scaffolded ARCHITECTURE/CONVENTIONS are stubs that MUST be populated via the brainstorming capture flow before structural implementation; mention the check script.
4. **verification-gate**: add an architecture-doc check for structural work — run `check-arch-docs.sh`, paste output as evidence.
5. **CHANGELOG**: `## [1.18.0]` entry (Added: capture→projection flow, check script, gate; Changed: brainstorming/project-scaffold/verification-gate/using-subteams).
6. **README/llms-install**: reflect the new pipeline step if architecture flow is documented there.
7. **user-prompt-check hook**: add a branch that detects greenfield/structural signals and emits a `[subteams:scope]` advisory pointing to the architecture-capture flow.

## Verify / Review

- `bash -n scripts/check-arch-docs.sh`; run it against a fresh stub (must fail) and a populated fixture (must pass).
- prompt-evaluator: confirm new instructions trigger on a greenfield case and DON'T trigger on a small logic fix.
- code-reviewer + devils-advocate (parallel): coherence, scope creep, false-positive risk of the gate.
- verification-gate before commit.

## Risks & Nuances
- **False positives:** check script firing on legitimately doc-light projects. Mitigation: gate scoped to structural/greenfield, invoked by orchestrator in pipeline — NOT a global commit hook.
- **Marker brittleness:** if templates change markers, script must stay in sync — single contract section above is the source of truth.
- **Rollback:** `git checkout main && git branch -D feat/architecture-capture-pipeline`; backup tag `backup/pre-arch-capture-*`.
