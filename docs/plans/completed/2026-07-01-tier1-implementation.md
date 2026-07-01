# IMPL-PLAN — Tier 1: Honesty invariant + rails-into-subagent (option A)

**Slug:** tier1-planning-autonomy-honesty
**Spec:** docs/specs/2026-07-01-planning-autonomy-honesty-design.md (rev. after plan defense)
**Branch:** feat/tier1-planning-autonomy-honesty
**Target version:** 1.26.0
**Status:** COMPLETED 2026-07-01 — merged to local main (76baaaa), v1.26.0; public push pending (operator)
**Scope decision:** autonomy re-sequenced to Tier 2 (on Task Contract, structural enforcement); SubagentStart hook deferred to Tier 2. Verdict of 3-critic plan defense, accepted by operator.

---

## Completion condition (evidence-tied; no self-certification)

Tier 1 is DONE when ALL hold, each with observable evidence:
1. Every acceptance criterion below is DONE with linked evidence (command output / review verdict).
2. `code-reviewer` + `devils-advocate` ran on the diff (prompt-text changes = non-trivial logic for the methodology); critical/important findings resolved — evidence: findings lists. (architecture-guard already reviewed the design; re-run only if reviewers flag structural drift.)
3. `prompt-evaluator` pass on changed skills/agents (Section 6.5) — evidence: eval results, no regressions.
4. Security check proportionate to the diff (markdown/prompt changes only, no executable code): prompt-injection review of new instruction text — folded into code-review scope, no separate auditor unless reviewers flag concern. Evidence: reviewer statement.
5. Grep evidence: honesty block present + byte-identical in all 16 agents; `Rails:` field in briefing template; JSON validity of both bumped .claude-plugin files.
6. ADRs 004–006 written; CHANGELOG + both version files bumped to 1.26.0; marketplace description "12 agents" → 16 fixed; README updated.
7. Merged to local `main`, backup tag created then removed, plan moved to completed/. **Public `git push` left to operator.**

**Non-goals (Tier 1):** any autonomy semantics (Tier 2) · executing-plans edits (Tier 2) · SubagentStart hook (Tier 2, gated) · Task Contract threshold change (Tier 2) · risk-trigger governance (Tier 2) · session-start resume (Tier 2).

---

## Rollup

| Pkg | Title | DONE | WIP | TODO | BLOCKED | Acceptance |
|-----|-------|------|-----|------|---------|-----------|
| P1 | Honesty invariant | 4 | 0 | 0 | 0 | reviewed, fixed |
| P2 | Rails via briefing | 2 | 0 | 0 | 0 | reviewed, fixed |
| P3 | Review/eval/deploy | 5 | 0 | 0 | 0 | merged |

---

## P1 — Honesty invariant (Invariant B)

- [x] AC-1: `verification-gate` gains `## Claim Provenance` (trusted/attributed/unverified + anti-hedge + materiality) and `## When a Tool or Command Fails`; namespaced vs existing L89 arch-doc provenance — DONE (applied; passed code-reviewer + devils-advocate with fixes, commit eb143a5)
- [x] AC-2: `using-subteams` gains a short `## Honesty Invariant` pointer + one Red Flags row — DONE (applied; passed code-reviewer + devils-advocate with fixes, commit eb143a5)
- [x] AC-3: all 16 `agents/*.md` carry an identical compact honesty block (heading + 4 bullets) after `## Who You Are`; grep verifies count=16 + byte-uniformity — DONE (applied; passed code-reviewer + devils-advocate with fixes, commit eb143a5)
- [x] AC-4: `orchestrator-briefing` embeds honesty in the "every brief" pattern (parallel to L288-289) — DONE (applied; passed code-reviewer + devils-advocate with fixes, commit eb143a5)

## P2 — Rails via briefing channel

- [x] AC-5: `orchestrator-briefing` Complete Brief Template (L18-29) gains mandatory `Rails:` field — DONE (applied; passed code-reviewer + devils-advocate with fixes, commit eb143a5)
- [x] AC-6: subagent Output Contract (L212+) gains `Rails read:` acknowledgment line — DONE (applied; passed code-reviewer + devils-advocate with fixes, commit eb143a5)

## P3 — Review / eval / deploy

- [x] AC-7: code-reviewer + devils-advocate on the diff; critical/important resolved — DONE (2 MAJOR + 2 IMPORTANT + 2 MEDIUM + 1 MINOR fixed in eb143a5; nits accepted; evidence in review outputs)
- [x] AC-8: prompt-evaluator pass — DONE (12 scenarios: 11 PASS, 1 FAIL agent-architect.md:29 stale enumeration + 3 minor; all 4 fixes applied. Anti-hedge confirmed: no disclaimer spam on TRUSTED facts)
- [x] AC-9: verification sweep — DONE (16/16 single hash cc13fba1; zero stale enumerations; JSONs valid @1.26.0; "12 specialized" purged; Four-rules wording present; tree scope = expected 12 files)
- [x] AC-10: ADRs 004-006 written; CHANGELOG [1.26.0] added; both version files → 1.26.0; "12 agents" → 16; README updated (3 clauses: briefing row, verification-gate row, Agents intro) — DONE
- [x] AC-11: backup tag → merge 76baaaa to local main → tag removed → plan moved to completed/ — DONE. Public push = operator (pending).

---

## Task breakdown (dispatch order)

1. **Author all text blocks** (prompt-engineer): 4-line agent block; verification-gate two sections; using-subteams pointer + Red Flags row; briefing Rails field + honesty embed + Rails-read ack. → P1, P2
2. **Apply edits** (developer): verification-gate, using-subteams, orchestrator-briefing, 16 agents. → P1, P2
3. **Review** (code-reviewer + devils-advocate, parallel) → fix. → P3
4. **prompt-evaluator** → fix regressions. → P3
5. **Verification sweep** (orchestrator): grep uniformity, JSON validity, evidence collection. → P3
6. **Docs & version** (doc-agent): README, CHANGELOG, ADR 004-006, version bumps. → P3
7. **finishing-branch**: backup tag, merge local main, cleanup, move plan. → P3

---

## Risks & Nuances

- **R1 — 16-file honesty drift.** Mitigation: single authored block applied verbatim; grep byte-uniformity check in AC-3/AC-9.
- **R2 — provenance vocabulary collision** (arch-doc "provenance" at verification-gate L89 / brainstorming L157). Mitigation: namespace "claim provenance".
- **R3 — disclaimer spam.** Without anti-hedge the invariant backfires. Mitigation: anti-hedge inside the block, non-optional; prompt-evaluator explicitly tests it.
- **R4 — portability.** Honesty text must carry zero host-specifics (no Telegram/notify.sh/paths from the source repo). Mitigation: prompt-engineer brief forbids them; reviewers check.
- **R5 — brief-template ripple.** Adding `Rails:` + honesty to the canonical brief affects every downstream skill that cites the template. Mitigation: reviewers check for contradictions with skills referencing orchestrator-briefing.
- **R6 — token weight.** 4 lines × 16 agents + brief embeds add constant overhead. Accepted: small, bounded, and the whole point is that it rides in every context. prompt-evaluator sanity-checks that blocks don't distort agent behavior.
