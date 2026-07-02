# IMPL-PLAN — Tier 2: Task Contract + structurally-enforced scoped autonomy (1.27.0)

**Slug:** tier2-contract-autonomy · **Branch:** feat/tier2-contract-autonomy · **Target:** 1.27.0
**Spec:** docs/specs/2026-07-01-planning-autonomy-honesty-design.md §3
**Status:** COMPLETED 2026-07-02 — merged to local main, v1.27.0, public push pending. Original: rev. 2 — plan defense DONE (devils-advocate + architecture-guard + Codex, all findings merged); operator approved the PreToolUse enforcement hook. In execution.
**Empirical inputs:** SubagentStart sentinel PASSED on CLI 2.1.197 (token round-trip confirmed). PreCompact re-hydration test NOT needed: the PreToolUse gate reads the run record from disk on every write-tool call, so enforcement survives compaction regardless of agent memory.

## Plan-defense verdict (folded in)
All three critics converged: autonomy-check.sh's *arithmetic* was structural but its *invocation* was voluntary — posture one level deeper. Resolution (operator-approved): a blocking **PreToolUse hook** on write-capable tools, env-gated (inert when `CLAUDE_SUBTEAMS_AUTONOMY` unset, coord-notify precedent), enforcing scope/caps BEFORE each edit. With it, the feature honestly carries the name "bounded autonomous execution". Controls that remain prose (re-hydration instruction, kill-switch, self-assessed risk-triggers) are explicitly labeled **behavioral protocol**, not structure. Checkpoints are review-light by design: deterministic exit codes mid-run; reviewer-disagreement is an end-of-run class, not a mid-run gate — documented as such.

---

## Completion condition (evidence-tied; no self-certification)

DONE when ALL hold, each with observable evidence:
1. Every AC below DONE with evidence (command output / review verdict / executed test).
2. Triple review on diff (code-reviewer + architecture-guard + devils-advocate) + Codex critics; critical/important resolved.
3. test-engineer adversarial tests for ALL shell artifacts (autonomy-check.sh, autonomy-gate hook, subagent-rails, session-start, check-plan.sh additions) — executed, output pasted. Must include: untracked-new-file, rename (--name-status), revision-free plan passes, env-unset inertness, non-git repo → ineligible, stale/expired/session-mismatched record → fail-closed, out-of-scope deny.
4. security-auditor on hooks/scripts — no High/Critical.
5. prompt-evaluator on skill text — no regressions (double-honesty-block via rails hook NOT flagged as regression — known benign duplication).
6. Verification sweep: bash -n all shell; hooks.json valid; per-AC greps; shipped-hook sentinel re-test (subagent-rails) capturing raw payload keys.
7. ADR-007 (enforcement architecture) + ADR-006 amendment (sentinel result, CLI 2.1.197, payload keys) + CHANGELOG [1.27.0] + both version files + using-subteams frontmatter version + README; merge to local main + v1.27.0; plan → completed/. **Public push = operator.**

**Non-goals:** Tier 3 · REVISE git-diff policing (format/anchor check only) · always-on enforcement in manual mode (hook is inert without env + fresh record) · mid-run reviewer dispatch (end-of-run only, honest docs) · wall-clock budget beyond expiry (grant expiry covers it; no separate clock cap) · retro-editing historical specs.
**Rollback risk (accepted, one release):** a defect in autonomy-check.sh / hooks post-ship means reverting 1.27.0 wholesale, incl. the co-bundled contract changes — operator's explicit single-release choice.

---

## Rollup

| Pkg | Title | DONE | WIP | TODO | BLOCKED | Acceptance |
|-----|-------|------|-----|------|---------|-----------|
| P1 | Task Contract (3a) | 6 | 0 | 0 | 0 | implemented |
| P2 | Risk-trigger governance (3c) | 3 | 0 | 0 | 0 | implemented |
| P3 | Autonomy: record + script + HOOK (3b) | 7 | 0 | 0 | 0 | implemented + session-match added |
| P4 | session-start resume (3d) | 2 | 0 | 0 | 0 | implemented (unset=silent) |
| P5 | SubagentStart rails hook (3e) | 2 | 1 | 0 | 0 | built; shipped-sentinel pending |
| P6 | Review/test/security/docs/deploy | 7 | 0 | 0 | 0 | done |

---

## P1 — Task Contract (3a)

- [x] AC-1: threshold removed/reworded at ALL sites: living-plan SKILL.md L3, L10, L12, **L15 ("when unsure… it probably does not" — replaced: contradicts risk-routing)**, Rule 1 L51; **writing-plans:21 (authoring-time copy — the load-bearing one)**; templates/IMPL-PLAN.md L8; **README.md:152**. New gate: **two artifact weights** — light contract (one screen: scope, acceptance criteria, non-goals; for risk-triggered or multi-session single-feature work) vs full matrix (packages+rollup; genuine multi-package/TZ work). Tiebreak explicit: risk-trigger wins for WRITING the artifact; process depth stays per pipeline tier. 4 worked examples calibrate the boundary. Anti-bureaucracy guard retained for trivial tasks — DONE (implemented; pending review/tests)
- [x] AC-2: write-once acceptance criteria + append-only `REVISED:` notes in living-plan Lifecycle + template. REVISED line changing scope/acceptance MUST carry an operator-ack token (quoted operator message) — the audit anchor. Template gains delimited **operator-owned** (criteria, grant) vs **agent-owned** (progress, checkpoints) sections — DONE (implemented; pending review/tests)
- [x] AC-3: subagent-driven-dev plan-of-record upkeep (mirror executing-plans L16) in Step 2 cycle + Verification Rules — DONE (implemented; pending review/tests)
- [x] AC-4: check-plan.sh REVISED **conditional** format+anchor check (validates only existing `REVISED:` lines; zero-REVISED plans still exit 0; scope/acceptance REVISED without ack-token → fail) — DONE (implemented; pending review/tests)
- [x] AC-5: code-review skill: contract path in `Rails:`, review diff against WRITTEN criteria (original + REVISED), not paraphrase — DONE (implemented; pending review/tests)
- [x] AC-6: run-record **schema pinned as deliverable BEFORE parser** (below) — template comment documents it — DONE (implemented; pending review/tests)

**Run-record schema (line-oriented, grep/awk only, NO jq; lives in the active IMPL-PLAN inside `<!-- autonomy-run:begin/end -->` markers):**
`AUTONOMY_GRANT:` (verbatim operator text, 1 line) · `AUTONOMY_CRITERIA_SNAPSHOT:` (N lines, immutable copy at grant — anti-goalpost-drift) · `AUTONOMY_SCOPE:` (comma-separated globs) · `AUTONOMY_BASE_COMMIT:` (sha) · `AUTONOMY_SESSION:` · `AUTONOMY_GRANTED_EPOCH:` / `AUTONOMY_EXPIRES_EPOCH:` (max TTL; expiry IS the wall-clock bound) · `AUTONOMY_MAX_FILES/LINES/TASKS:` (per-interval) · `AUTONOMY_BUDGET_FILES/TASKS:` (aggregate) · `AUTONOMY_CHECKPOINT:` lines **appended by autonomy-check.sh itself** (script-authored, not agent-authored — closes the self-graded-counter hole).

REVISED: dropped AUTONOMY_MAX_TASKS/AUTONOMY_BUDGET_FILES/AUTONOMY_BUDGET_TASKS and the "per-interval" vs "aggregate" caps split from the schema above — superseded by a single TOTAL-RUN files/lines cap pair (AUTONOMY_MAX_FILES/AUTONOMY_MAX_LINES only, recomputed fresh from git on every call, never from checkpoint history) — "operator approved simplification during Tier 2 review"

## P2 — Risk-trigger governance (3c)

- [x] AC-7: using-subteams §6 criteria: risk-triggers as depth selectors (schema/data-invariant, public API, new dependency/stack, destructive migration, security boundary, ambiguous intent, autonomous execution, large blast radius); file-count → effort only. Objective vs self-assessed triggers labeled honestly — DONE (implemented; pending review/tests)
- [x] AC-8: Standard step 1 routes risk-triggered work to a **light contract** (not full matrix, not Full-pipeline gates — adds ONLY the artifact) — DONE (implemented; pending review/tests)
- [x] AC-9: living-plan added to §5 Specialist Catalog; using-subteams frontmatter version bumped — DONE (implemented; pending review/tests)

## P3 — Autonomy (3b): record + script + hook

- [x] AC-10: executing-plans Step 4 mode-aware + Red Flag L113 + ALWAYS-block consistency, in lockstep — DONE (implemented; pending review/tests)
- [x] AC-11: `## Autonomy Mode` section (inline; split-trigger documented: if file >200 lines or section >40% → Tier 3 dedicated skill): activation contract, failure classes (cap-exceeded & out-of-scope = operator-decision-required, STRUCTURAL via hook; reviewer-disagreement = end-of-run), verifiability precondition, kill-switch + re-hydration as labeled behavioral protocol, banner isolating section from interactive readers. using-subteams gets a POINTER (one authoritative home) — DONE (implemented; pending review/tests)
- [x] AC-12: `scripts/autonomy-check.sh` per architecture-guard interface: args like check-plan.sh; deps git/grep/awk ONLY; env gate first (unset → exit 3); plan selection (0 or >1 active records → exit 4); freshness (expiry epoch, session match, base commit exists — else exit 4 fail-closed, distinct from violation); scope eval = `git diff --name-only $BASE` ∪ `git ls-files --others --exclude-standard`, `--name-status` for renames, glob match (violation → exit 2); caps per-interval + aggregate budget from script-authored checkpoint lines; **fail-closed everywhere: 2/3/4 all mean STOP, only 0 proceeds** (R2 wording folded in); non-git → exit 4; multi-instance: other live instances in coord.sh roster → exit 4 ineligible (single-writer) — DONE (implemented; pending review/tests). **Fix batch #2 (G1/G5):** `--pending` and the record-exemption comparison canonicalized (realpath -m / readlink -f / raw-string degrade) and rejected when the resolved form escapes the repo root (exit 2); LINES cap recomputed over the changed-file set MINUS the record file (numstat + untracked wc -l), no longer whole-repo `--shortstat` — a record-only diff now reports lines=0.
- [x] AC-13: **`hooks/autonomy-gate` (PreToolUse, matcher Edit|Write|Bash, async:false):** env unset → instant exit 0 (zero manual-mode impact); env set + fresh record → runs autonomy-check.sh, exit 2/3/4 → `permissionDecision: deny` with reason; no active record → exit 0 (autonomy not in progress); registered in hooks.json — DONE (implemented; pending review/tests). **Fix batch #2 (G1/G2/G3/G4):** the record-edit deny now canonicalizes both the incoming target and each candidate record path (closes relative/`../`/symlink-alias bypasses); `PROJECT_DIR` resolves to the git repo root before the record scan (closes the cwd-subdirectory fail-open); NotebookEdit's `notebook_path` field is now read as the effective target alongside `file_path`, closing the field-name gap that left it uncovered; a Bash command referencing the record's basename or the literal `autonomy-run` marker is denied as a BEST-EFFORT pattern-match (does not close the general Bash post-hoc vector — indirection via variables/python/base64/etc. still evades it; the residual is a deferred operator decision, not solved here).
- [x] AC-14: env honestly framed: the HOOK is enforcement; script alone = checkpoint evidence; skill text says exactly this — DONE (implemented; pending review/tests)
- [x] AC-15: using-subteams autonomy doctrine paragraph + Red Flags row; "assisted continuation" naming rule recorded for configs without the hook — DONE (implemented; pending review/tests)
- [x] AC-16: checkpoint gate: each autonomy checkpoint carries ≥1 deterministic exit code (autonomy-check.sh and/or tests); wired into Autonomy Mode + verification-gate cross-ref — DONE (implemented; pending review/tests)

## P4 — session-start resume (3d)

- [x] AC-17: active-plans block upgraded: ≤3 plans × 1 line (name, age days, next non-DONE, BLOCKED count) + single cached check-plan.sh verdict; recommend-not-command; echo-only — DONE (implemented; pending review/tests)
- [x] AC-18: autonomy line worded capability-only: "autonomy gate env: set/unset (an active run still requires a fresh contract record)" — DONE (implemented; pending review/tests)

## P5 — SubagentStart rails hook (3e)

- [x] AC-19: `hooks/subagent-rails`: fires FOR subagents (**guard polarity: never a presence-based skip — coord-notify's guard is the INVERSE**); static plugin-authored text only (rails pointer + 1-line honesty reminder); silent-fail — DONE (implemented; pending review/tests)
- [x] AC-20: hooks.json: `"SubagentStart"`, matcher `""`, async:false, timeout 5000 — DONE (implemented; pending review/tests)
- [x] AC-21: shipped-hook sentinel re-test capturing RAW payload keys (agent_id/agent_type presence on 2.1.197) → recorded in ADR-006 amendment — DONE

## P6 — Review / test / security / docs / deploy

- [x] AC-22: triple review + Codex on diff; critical/important resolved — DONE
- [x] AC-23: test-engineer adversarial suite (list in Completion condition #3), executed — DONE
- [x] AC-24: security-auditor on autonomy-gate + subagent-rails + autonomy-check.sh + session-start — DONE
- [x] AC-25: prompt-evaluator on skill text — DONE
- [x] AC-26: verification sweep (bash -n, JSON, greps, shipped sentinel) — DONE
- [x] AC-27: ADR-007 + ADR-006 amendment + CHANGELOG + versions (plugin.json, marketplace.json, using-subteams frontmatter) + README; merge + v1.27.0 + cleanup — DONE

---

## Risks & Nuances
- R1 threshold wording bias → two-weight artifact + tiebreak + examples (AC-1); devils-advocate re-checks wording on diff review.
- R2 false blocks → exit 4 ("cannot evaluate", fail-closed w/ distinct message) vs exit 2 (violation); rename/untracked/base-gone covered in tests.
- R3 goalpost drift → criteria snapshot in record + operator-ack token on scope REVISED + external review vs snapshot.
- R4 hook perf: PreToolUse spawn per write-call; env-unset path is a 2-line exit (measured in tests); precedent coord-notify on PostToolUse.
- R5 hook deadlock: autonomy-gate must NOT invoke anything that itself triggers PreToolUse (pure shell, no claude calls).
- R6 subagent writes during autonomy: hook fires in subagent tool-calls too (same session env) — intended: subagents inherit the scope gate.
- R7 stale docs: doc-quality-gate / session-end-reminder verified NOT threshold-stale (generic wording); historical specs untouched.
- R8 two version files + skill frontmatter — sweep asserts all three.
