# Design Spec: Planning, Scoped Autonomy & Honesty Invariant

**Date:** 2026-07-01
**Status:** APPROVED (operator, option A) — Tier 1 in implementation
**Target version:** 1.26.0 (Tier 1); Tier 2–3 follow in later releases
**Author:** orchestrator (agent-engineering rulebook), from a multi-agent study (6 analysts + Claude & Codex critics), revised after plan defense (devils-advocate + architecture-guard + Codex, 2026-07-01)

---

## 0. Problem & framing

The operator is a solo developer. The plugin already has strong mechanisms (`brainstorming`, spec format, `living-plan` matrix, cross-review) but they are **structurally unreachable on the common path**: the pipeline classifier decides tier by file-count *before* deciding whether the task is understood, so `Standard` (the most frequent path) emits no durable artifact, no spec, no design. Empirically `docs/specs/` holds ~1 file and `docs/adr/` was long empty.

Goal: make planning + documentation good enough to **optionally** launch autonomous sessions that do not degrade, **without** turning the plugin into a mandatory process framework (micromanagement).

### Governing insight (from the study, accepted after adversarial review)

> **Artifact value scales with the operator's ABSENCE, not with task complexity.**
> Manual mode (default) = operator in the loop = spec/design docs mostly redundant.
> Autonomy (opt-in, rare) = operator out = the artifact is the only safety net.

### Plan-defense verdict that re-sequenced this spec (option A)

Three independent critics (devils-advocate, architecture-guard, Codex) converged: an autonomy mode built **before** the canonical Task Contract exists would be backed only by prompt posture — self-assigned failure classes, caps that notify instead of block, an env "gate" nothing executable reads, no re-hydration after compaction, and a contract the same agent rewrites. That is exactly the confidence theater this initiative rejects. **Therefore: autonomy moves to Tier 2, where it is built ON the Task Contract with structural (diff-based, machine-checkable) enforcement. Tier 1 ships the two invariants that are real today: honesty posture + rails delivery.**

### Non-negotiables carried from the study

1. Manual-first. Autonomy is an explicitly-scoped per-command grant, never an ambient default. The milestone human pause is a **deliberate safety boundary**.
2. No confidence theater. Safety claims must be backed by structural controls (diff comparison, exit codes, write-once records), not by the agent's self-description. More self-graded internal gates *increase* the illusion of completion. The cross-model (Codex) adversary works because it is **rare and external**.
3. Honesty is a **posture**, not a mandatory research ritual. Research is obligatory only for *material* claims. Anti-hedge is mandatory (verified facts stated plainly, no disclaimer spam).
4. Do NOT rebuild Full inside Standard. Depth is a budgeted response to risk.

---

## 1. The three invariants (scope of the whole initiative)

### Invariant A — One canonical Task Contract (Tier 2)
Extend the existing `living-plan` matrix into the single source of truth every actor reads/writes. **Write-once acceptance criteria** (original criteria immutable; changes append as revision notes, never rewrite) + append-only run state. Drop the "≥2 packages" threshold; route by **risk-triggers** instead of file-count.

### Invariant B — Honesty posture + material-claim research (Tier 1)
Tool failure → say so, never fabricate. External claim → mark provenance (trusted / attributed / unverified). Verified facts stated as fact, no hedge. Research obligatory only when a claim is *material* (architecture, dependency, visible behavior, external compatibility, security, contested fact).

### Invariant C — Autonomy as a scoped command (Tier 2, on top of A)
Manual pipeline **minus** the human pause **plus** bounded, evidence-carrying checkpoints — with **structural** enforcement (see §3). Depends on the Task Contract; not buildable honestly before it.

### Rails-into-subagent delivery (Tier 1, briefing channel)
Guarantee every spawned subagent receives the project rails (CONVENTIONS.md / ARCHITECTURE.md pointer, active plan path) + the honesty invariant, via a mandatory `Rails:` brief field and a rails-read acknowledgment in the subagent output contract. A `SubagentStart` hook is a Tier 2 option, gated on an empirical delivery test (see §3).

---

## 2. Tier 1 — detailed design (this release, 1.26.0)

Tier 1 = Invariant B everywhere + rails delivery via the briefing channel. No autonomy semantics ship in Tier 1.

### T2.1 Honesty invariant

**Content** (adapted from the operator's battle-tested `claudebot-arendada` honesty block; all host-specifics stripped — portability is a hard requirement):

```
Honesty invariant:
- Tool/command failure, empty or stale result → state it plainly. Never fill the gap with a guess.
- Every external claim carries provenance: TRUSTED (verified this session / from the repo → state as fact),
  ATTRIBUTED (source + date), or UNVERIFIED (recall, may be 6–18 months stale → say so).
- Anti-hedge: trusted/verified facts are stated as fact, WITHOUT disclaimers. Do not hedge what you verified.
- Research is obligatory only for MATERIAL claims — those that affect architecture, a dependency choice,
  user-visible behavior, external compatibility, security, or a contested fact. Trivial claims get an
  explicit uncertainty label, not mandatory browsing.
```

**Placement (four homes; detail lives in ONE place, the rest are pointers/compact blocks):**
1. `skills/verification-gate/SKILL.md` — authoritative detail:
   - new `## Claim Provenance` section (~L15, Overview-adjacent). **Namespaced "claim provenance"** to avoid collision with the existing arch-doc "provenance" at L89.
   - new `## When a Tool or Command Fails` section (~L43). Mirrors the existing explicit-honesty phrasing at L101.
2. `skills/using-subteams/SKILL.md` — short `## Honesty Invariant` pointer + one Red Flags row.
3. All 16 `agents/*.md` — an identical compact 4-line block right after `## Who You Are` (the one anchor present in all 16). Byte-identical across agents; a grep check in the verification sweep asserts presence + uniformity (guards drift over time).
4. `skills/orchestrator-briefing/SKILL.md` — honesty added to the "include in EVERY brief" embed pattern (parallel to L288-289).

**Materiality threshold, not mechanical trigger:** explicitly reject "library name / version / 'latest' → research mandatory" (source laundering + spam). Consistent with the existing 30-second rule (using-subteams §4).

### T2.2 Rails-into-subagent (briefing channel)

- `skills/orchestrator-briefing/SKILL.md`, Complete Brief Template (L18-29): new mandatory field
  ```
  Rails: [path(s) the subagent MUST read before acting — project conventions/architecture docs
          (e.g. docs/CONVENTIONS.md, docs/ARCHITECTURE.md) and the active plan/contract in
          docs/plans/active/, when they exist]
  ```
- **Rails-read acknowledgment** (Codex suggestion, accepted): the subagent Output Contract (L212+) gains a line — `Rails read: <path(s)> — "<constraint quote>" applied at <file:line>`. An attention prime + spot-check anchor (quote and file:line are cross-referable in seconds), honestly NOT a guarantee — a posture-tier control, per review.
- The subagent's own prompt is the **only 100%-guaranteed delivery channel** (hooks research) — so this field is the floor regardless of any future hook.

### T2.3 SubagentStart hook — deferred to Tier 2 (decision, ADR-006)

All three critics independently recommended cutting the hook from Tier 1: the event exists (Claude Code changelog; ≥2.1.19x), but `additionalContext` support on SubagentStart is *not* documented (changelog grants it explicitly only to Stop/SubagentStop), the briefing field already provides the guaranteed floor, and an every-subagent injection hook is a new prompt-injection surface that deserves its own threat model (the plugin's `coord-notify` deliberately refuses to inject peer content; `session-start` states "minimal, no prompt injection"). Deferring removes hooks.json changes and shrinks Tier 1 blast radius at zero cost to the goal.

**Carried to Tier 2 with constraints fixed now:** if built, the hook must be `"async": false` (async hooks' additionalContext is ignored — per coord-notify L19), matcher `""` not `"*"` (house style; `*` is invalid regex in some harness versions), registered only **after** a sentinel delivery test passes on the operator's CLI version, and inject **only static plugin-authored text/paths** — never project-authored file contents (prompt-injection hygiene, mirroring coord-notify).

---

## 3. Tier 2 — autonomy with a spine (design level, next release(s))

Order matters: **A first, then C on top of it.**

### 3a. Task Contract (Invariant A)
- Drop `living-plan`'s "≥2 packages" threshold; classifier routes risk-tasks (see 3c) into the matrix.
- **Write-once acceptance criteria:** original criteria are immutable once the operator approves the plan; any change is an append-only revision note (`REVISED: <what> — <why> — <operator ack if scope/acceptance changed>`). This is the anti-goalpost-drift control: "am I on scope?" is always answered against the *original* criteria + explicit revisions, never a silently rewritten doc.
- **All executors update the matrix** — including `subagent-driven-dev` (today it does not; the matrix dies when it is chosen).
- Reviewer briefs carry the contract path; reviewers verify the diff against **written acceptance criteria**, not a paraphrase.

### 3b. Scoped autonomy (Invariant C) — structural enforcement, not posture
Every control below is machine-checkable; none rely on the agent's self-description:
- **Diff-based scope gate:** at every checkpoint, `git diff --name-only` vs the contract's declared file scope. Any out-of-scope path ⇒ automatic `operator-decision-required` (structural, not self-assessed). Pre-authorized exceptions must be listed in the contract *before* the run.
- **Blocking caps + total run budget:** exceeding `CLAUDE_SUBTEAMS_AUTONOMY_MAX_FILES/LINES/TASKS` **blocks** (it is `operator-decision-required`, not a notify-and-continue). A **total-run budget** (cumulative files/tasks/wall-clock) hard-stops the run — caps are per-interval AND aggregate.
- **Non-fakeable checkpoint gate:** each checkpoint must carry at least one gate the agent cannot self-grade: a deterministic command exit code (tests/lint) or, for high-stakes runs, the rare Codex adversary anchored to the written contract criteria. A task with no such external verifier is **not eligible** for autonomy.
- **Re-hydration after compaction:** the #1 killer of long runs. On any compaction/context-loss event, the agent MUST re-read the contract + rails before the next action. **Fail-closed:** if the "autonomy granted, scope = X" record is not recoverable verbatim from the contract, revert to interactive and re-confirm — never continue on a remembered grant.
- **Run record:** activation writes a visible record into the contract (grant text, scope, timestamp/session, expiry); every checkpoint restates it. Absent a fresh record ⇒ interactive path. The env var `CLAUDE_SUBTEAMS_AUTONOMY` is honestly named an **instruction precondition** (nothing executable enforces it today); if a real gate is wanted, a hook must read it (Tier 2 build decision).
- **Kill-switch:** a documented mid-run interrupt (operator message = immediate `operator-decision-required` checkpoint at the next tool boundary).
- **Failure classes** (operator-decision-required / external-evidence-required / reviewer-disagreement / local-fixable / informational) remain, but the first is triggered *structurally* (scope diff, cap, lost record) in addition to semantically.
- **Risk-over-volume:** volume caps are subordinate to semantic risk triggers (destructive ops, schema/migration, auth/security boundary, dependency/tooling/hook/prompt change, API contract) — any of these ⇒ blocks regardless of diff size.
- Naming: honest scope claim — this is **bounded autonomous execution** only once ALL of the above exist; anything less is "assisted continuation" and must not be marketed as autonomy.

### 3c. Governance on risk-triggers, not file-count
Risk-triggers become first-class selectors of depth (spec / design / security review); file-count only estimates effort.

### 3d. `session-start` resume
Print plan name / age / next non-DONE criterion / blockers + `check-plan.sh` result; recommend (not command) resume.

### 3e. SubagentStart hook (from T2.3, if the sentinel test passes)

## 4. Tier 3 — deferred (only if usage proves need)
- Spec/plan review against written criteria + optional Codex gate on high-stakes/autonomous only.
- Dedicated `autonomous-execution` skill if executing-plans edits prove insufficient.
- In-code deferred-deviation marker → harvestable ledger (ponytail pattern) mapped onto contract revision notes.

## 5. Explicitly REJECTED (anti-micromanagement + anti-theater guardrails)
Do NOT: mandate interview/spec/design for all Standard work · mechanical research triggers by pattern · REVISE enforcement via git-diff in check-plan.sh · bridge two classifications (delete an axis instead) · three cross-model gates · drift-owner / provenance scripts · a new standalone honesty skill · revive the dead adr-tracker · scaffold ARCHITECTURE/CONVENTIONS dupes · a parallel autonomy pipeline with its own gates · **ship autonomy semantics backed only by prompt posture (the reason autonomy is Tier 2)**.

## 6. Borrowed from ponytail (patterns, not code; MIT, attributed)
1. `SubagentStart` re-injection plumbing → Tier 2 (gated).
2. In-code deferred-deviation marker → ledger → Tier 3.
3. Scoped-mode ergonomics (env/config default + whole-message-only *deactivation*; activation = explicit grant restated in the run record) → Tier 2 autonomy.
4. "Do not fabricate a baseline-less metric" honesty phrasing → T2.1 provenance wording.
Do NOT install ponytail alongside (two SessionStart injectors + a "write less code" bias vs contract completeness).

## 7. Deploy (Tier 1)
Version 1.25.0 → **1.26.0** (feat = minor). Bump `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (both carry the version; there is no root plugin.json), `CHANGELOG.md`. While touching marketplace.json, fix the stale "12 specialized sub-team agents" → 16. ADRs: 004 (honesty invariant placement), 005 (autonomy re-sequenced to Tier 2 on structural-enforcement grounds), 006 (SubagentStart hook deferred; constraints recorded). Work on `feat/tier1-planning-autonomy-honesty`; full pipeline; merge to local `main` + tag; **operator performs the public `git push`**.

## 8. Files touched (Tier 1, final)
- `skills/verification-gate/SKILL.md` — Claim Provenance + tool-failure sections
- `skills/using-subteams/SKILL.md` — honesty pointer + Red Flags row
- `skills/orchestrator-briefing/SKILL.md` — mandatory `Rails:` field + rails-read ack in Output Contract + honesty-in-every-brief
- `agents/*.md` (16) — compact honesty block (heading + 4 bullets, incl. materiality) after `## Who You Are`; researcher.md additionally maps confidence↔claim-provenance taxonomies
- `skills/subagent-prompt-design/SKILL.md` + `skills/agent-engineering/SKILL.md` — output-contract enumerations synced with the new `Rails read:` field (R5 ripple found in review)
- `docs/adr/004..006-*.md` (new), `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — version + decisions
- `README.md` — feature docs (doc-agent)
- NOT touched in Tier 1: `skills/executing-plans/SKILL.md` (autonomy → Tier 2), `hooks/*` (hook deferred)
