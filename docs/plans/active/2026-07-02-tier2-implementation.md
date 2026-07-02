# IMPL-PLAN — Tier 2: Task Contract + structurally-enforced scoped autonomy (1.27.0)

**Slug:** tier2-contract-autonomy
**Spec:** docs/specs/2026-07-01-planning-autonomy-honesty-design.md §3 (Tier 2 blueprint, reviewed at Tier 1 plan defense)
**Branch:** feat/tier2-contract-autonomy
**Target version:** 1.27.0 (operator chose: whole Tier 2 in one release)
**Status:** DRAFT — awaiting plan defense

**Empirical input:** SubagentStart sentinel test PASSED on CLI 2.1.197 (2026-07-02) — a `SubagentStart` hook's `hookSpecificOutput.additionalContext` was received verbatim by a spawned subagent (token `SENTINEL_RAILS_XYZ123` repeated back). The rails hook (P5) is buildable for real, under ADR-006 constraints.

---

## Completion condition (evidence-tied; no self-certification)

Tier 2 is DONE when ALL hold, each with observable evidence:
1. Every AC below DONE with linked evidence (command output / review verdict / test result).
2. Plan defense ran (devils-advocate + architecture-guard + Codex, in parallel, on this plan) and critical findings were addressed before implementation.
3. Triple review on the diff (code-reviewer + architecture-guard + devils-advocate) + Codex critics; critical/important resolved.
4. **test-engineer wrote and ran adversarial tests for all shell artifacts** (autonomy-check.sh, session-start additions, subagent-rails hook, check-plan.sh additions) — real executed tests, not review; output pasted.
5. **security-auditor pass on the new hook + scripts** (injection surface, path handling, env handling) — no High/Critical.
6. prompt-evaluator pass on changed skill text; no regressions.
7. Verification sweep: `bash -n` all touched shell files; hooks.json valid JSON; grep evidence for every AC; sentinel re-test of the SHIPPED subagent-rails hook (not just the fixture).
8. ADR-007 (structural autonomy enforcement decisions) written; ADR-006 amended with the sentinel result; CHANGELOG [1.27.0]; both version files bumped; README updated.
9. Merged to local `main` + tag v1.27.0; backup tag removed; plan moved to completed/. **Public push = operator.**

**Non-goals:** Tier 3 items (spec §4) · rewriting Full/Lightweight pipelines · any always-on enforcement for manual mode (autonomy controls activate only inside a granted run) · REVISE policing via git-diff in check-plan.sh (spec §5 explicitly forbids; format-check only).

---

## Rollup

| Pkg | Title | DONE | WIP | TODO | BLOCKED | Acceptance |
|-----|-------|------|-----|------|---------|-----------|
| P1 | Task Contract (3a) | 0 | 0 | 5 | 0 | pending |
| P2 | Risk-trigger governance (3c) | 0 | 0 | 3 | 0 | pending |
| P3 | Scoped autonomy, structural (3b) | 0 | 0 | 6 | 0 | pending |
| P4 | session-start resume (3d) | 0 | 0 | 2 | 0 | pending |
| P5 | SubagentStart rails hook (3e) | 0 | 0 | 3 | 0 | pending |
| P6 | Defense/review/test/security/docs/deploy | 0 | 0 | 7 | 0 | pending |

---

## P1 — Task Contract (Invariant A)

- [ ] AC-1: `living-plan` threshold removed in all 4 spots (SKILL.md L3 description, L10, L12, Rule 1 L51) — new gate: risk-triggered or multi-criterion work, not "≥2 packages only"; explicit anti-bureaucracy guard retained (no matrix for trivial single-step tasks) — TODO
- [ ] AC-2: write-once acceptance criteria + append-only revision notes in `living-plan` Lifecycle (§3, between Author and Update) and `templates/IMPL-PLAN.md` (threshold comment L8 reworded; `REVISED: <what> — <why> — <operator ack if scope/acceptance changed>` line format documented at criteria L24-25) — TODO
- [ ] AC-3: `subagent-driven-dev` updates the matrix — plan-of-record upkeep paragraph (mirroring executing-plans L16) wired into Step 2 per-task cycle (after "mark task complete" L50) and Verification Rules — TODO
- [ ] AC-4: `check-plan.sh` gains a REVISED-line **format** check (regex near L27, new step in check_plan() after L78) — presence/shape only, NO git-diff policing — TODO
- [ ] AC-5: reviewer-against-contract: `code-review` skill briefing section instructs passing the active contract path in `Rails:` and reviewing the diff against its written acceptance criteria (not a paraphrase) — TODO

## P2 — Risk-trigger governance (3c)

- [ ] AC-6: `using-subteams` Section 6 criteria table gains risk-triggers as first-class depth selectors (data-invariant/schema change, public API/contract, new dependency/stack, destructive migration, security boundary, ambiguous intent, autonomous execution, large blast radius); file-count demoted to effort estimation — worded as an addition, existing tiers keep working — TODO
- [ ] AC-7: Standard Pipeline step 1 routes risk-triggered work to a living-plan matrix (contract) instead of ephemeral bullets; non-risk Standard stays bullets (anti-micromanagement) — TODO
- [ ] AC-8: `living-plan` added to Section 5 Specialist Catalog (Planning & flow row) — TODO

## P3 — Scoped autonomy with structural enforcement (3b)

- [ ] AC-9: `executing-plans` Step 4 milestone mode-aware (interactive: ask+wait unchanged; autonomy: non-blocking evidence checkpoint) + Red Flag L113 conditioned in lockstep + ALWAYS block consistency — TODO
- [ ] AC-10: new `## Autonomy Mode` section in `executing-plans`: activation contract (explicit per-message grant with scope; run record written into the contract: grant text, scope file-list, caps, expiry; no persistence — lost/stale record ⇒ fail-closed to interactive), failure classes with propagation (only `operator-decision-required` always blocks; cap-exceeded and out-of-scope ARE `operator-decision-required`), verifiability precondition, re-hydration after compaction (re-read contract + rails before next action), kill-switch (any operator message ⇒ checkpoint at next tool boundary), section visually isolated so interactive readers skip it — TODO
- [ ] AC-11: **new `scripts/autonomy-check.sh`** — the structural gate, run at every checkpoint, output pasted as evidence: validates run record exists & fresh in the active contract; `git diff --name-only <base>` vs declared scope (out-of-scope path ⇒ exit 2 operator-decision-required); counts files/lines vs caps `CLAUDE_SUBTEAMS_AUTONOMY_MAX_FILES/LINES/TASKS` (defaults 10/400/5) and total-run budget (cumulative, from run record); exit codes documented; defensive house style (set -uo pipefail, no deps beyond git/grep/awk, silent-degrade messages not crashes) — TODO
- [ ] AC-12: `CLAUDE_SUBTEAMS_AUTONOMY` env gate honestly framed: autonomy-check.sh refuses (exit 3) when unset — making the env a REAL precondition of the structural gate, not just prose; skill text says exactly that — TODO
- [ ] AC-13: `using-subteams` autonomy doctrine extended (Section 9/Red Flags region): scoped runs OK when explicitly granted + bounded + evidence-checkpointed; never extends to changing agreed plan/scope; "assisted continuation" naming rule when controls are absent — TODO
- [ ] AC-14: non-fakeable checkpoint gate documented: each autonomy checkpoint must carry ≥1 deterministic command exit code (tests/lint/autonomy-check.sh) — a checkpoint without one is invalid; wired into Autonomy Mode + verification-gate cross-reference — TODO

## P4 — session-start resume (3d)

- [ ] AC-15: `hooks/session-start` active-plans block (L14-19) upgraded: per-plan name, age (mtime days), next non-DONE criterion, BLOCKED count, `check-plan.sh` pass/fail — recommend (not command) resume; stays echo-only ("minimal, no prompt injection" charter), bounded output (max 3 plans, 1 line each + 1 summary line) — TODO
- [ ] AC-16: autonomy capability line: `[subteams] autonomy: CLAUDE_SUBTEAMS_AUTONOMY=<set/unset>` (informational) — TODO

## P5 — SubagentStart rails hook (3e)

- [ ] AC-17: new `hooks/subagent-rails`: SubagentStart, reads stdin JSON (agent_id guard like coord-notify), emits `hookSpecificOutput.additionalContext` with STATIC plugin-authored text only — a rails pointer instruction ("before acting, read docs/CONVENTIONS.md / docs/ARCHITECTURE.md / the active plan under docs/plans/active/ if they exist; your brief's Rails field lists the paths") + 1-line honesty reminder; NEVER embeds project file contents; silent-fail throughout — TODO
- [ ] AC-18: registered in `hooks.json`: `"SubagentStart"`, matcher `""`, `"async": false`, timeout 5000 — house style — TODO
- [ ] AC-19: shipped-hook sentinel re-test: headless child Claude with the plugin's actual hooks.json wiring (or equivalent settings) confirms delivery; result recorded in ADR-006 amendment — TODO

## P6 — Defense / review / test / security / docs / deploy

- [ ] AC-20: plan defense (devils-advocate + architecture-guard + Codex on THIS plan) — critical findings addressed pre-implementation — TODO
- [ ] AC-21: triple review + Codex on diff; critical/important resolved — TODO
- [ ] AC-22: test-engineer adversarial tests for autonomy-check.sh + session-start + subagent-rails + check-plan.sh additions (executed, output pasted) — TODO
- [ ] AC-23: security-auditor on hooks/scripts — no High/Critical — TODO
- [ ] AC-24: prompt-evaluator on skill-text changes — no regressions — TODO
- [ ] AC-25: verification sweep (bash -n, JSON validity, per-AC greps, shipped-hook sentinel) — TODO
- [ ] AC-26: ADR-007 + ADR-006 amendment + CHANGELOG [1.27.0] + version bumps + README; merge to local main + v1.27.0 + cleanup; plan → completed/ — TODO

---

## Risks & Nuances

- **R1 — Threshold removal floods trivial tasks with matrices.** Mitigation: AC-1 keeps an explicit anti-bureaucracy guard; AC-7 routes only risk-triggered Standard work; devils-advocate checks the wording bias.
- **R2 — autonomy-check.sh false blocks** (renames, generated files, base-commit detection). Mitigation: declared scope supports globs; base = run-record commit hash; test-engineer covers rename/glob/empty-diff cases; exit codes distinguish "violation" from "cannot evaluate" (fail-closed but with distinct message).
- **R3 — Write-once criteria vs legitimate replanning.** Revision notes are append-only and cheap; operator ack required only when scope/acceptance change (not cosmetics). check-plan.sh checks format only (spec §5 ban on diff-policing).
- **R4 — Autonomy Mode text weight in a skill Standard also reads.** Mitigation: visually isolated section with "applies ONLY inside an explicitly granted autonomy run" banner; interactive path text unchanged.
- **R5 — Hook injection surface.** subagent-rails injects static text only (coord-notify precedent); security-auditor gates it; matcher ""/async:false per ADR-006.
- **R6 — Env gate is real only via autonomy-check.sh.** If the orchestrator skips running the script, enforcement degrades to posture. Mitigation: checkpoint invalid without a deterministic exit code (AC-14); Red Flag row; honest framing in text.
- **R7 — session-start output bloat/perf.** Bounded to 3 plans × 1 line; check-plan.sh is fast (grep-based); async:false timeout 10s already in hooks.json.
- **R8 — Version-file duplication** (plugin.json + marketplace.json) — both bumped, sweep asserts equality.
