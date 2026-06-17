# Three-Idea Modernization — Implementation Plan

> **For agentic workers:** this is agentic/prompt work — `using-subteams` Section 6.5 applies (prompt-engineer authors prose, prompt-evaluator validates; agent-architect only where a new skill's topology/contract is designed). Each phase is its own pipeline cycle, branch, and version bump.

**Status:** All three shipped (2026-06-17) — Phase 1 ✅ (1.21.0), Phase 2 ✅ (1.22.0), Phase 3 ✅ reduced v1 (1.23.0). Phase 3 was cut to a coherent core after a plan-defense review (agent-architect + devils-advocate); **deferred to a future "3c" phase**: shared task ledger, hooks-as-quality-gates, SQLite backend, fencing tokens, and any PreToolUse "enforcement" hook (claims ship as honest advisory coordination).
**Author:** Bogdan + Claude Opus 4.8
**Specs:** [`docs/specs/2026-06-17-living-plan-ledger.md`](../../specs/2026-06-17-living-plan-ledger.md), [`docs/specs/2026-06-17-multiinstance-coordination.md`](../../specs/2026-06-17-multiinstance-coordination.md)
**Sequencing (approved):** 1 → 2 → 3, each shipped separately.

---

## Goal

Close three connective-tissue gaps in claude-subteams: (1) cross-cutting doc trackers drift because the freshness gate under-checks them; (2) the real "plan of record" for contracted work is scattered and invisible; (3) no substrate exists for several Claude Code instances to cooperate on one repo/one machine.

## Why phased

Idea 1 is ready (gap confirmed in code). Idea 2 plugs its refresh step into Idea 1's extended gate, so it must follow 1. Idea 3 is forward-looking and largest; its shared task ledger reuses Idea 2's matrix. Strict order avoids rework and keeps each change reviewable.

## Shared contract (all phases honor these)

- **Version line:** Phase 1 → **1.21.0**, Phase 2 → **1.22.0**, Phase 3 → **1.23.0**. Bump in `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` + the touched skill's own version line.
- **Backend for any coordination/ledger state:** file-based primary (markdown / flock / JSON), SQLite optional only where the host project already runs it. No new mandatory runtime dependency.
- **In-context authorship rule:** orchestrator authors living docs (plan-of-record, arch docs) from real source material; gaps marked `**TBD — unresolved**`, never invented. Same discipline as the architecture-capture pipeline (v1.18.0).
- **Per phase:** feature branch `feat/<phase>`, backup tag `backup/pre-<phase>-<ts>`, prompt-evaluator pass before merge, CHANGELOG entry, version-bump recurring checklist (README/INSTALL/llms-install/templates).

---

## Phase 1 — Doc-freshness triad fix (Idea 1) → v1.21.0   ✅ SHIPPED (merged 1.21.0, 2026-06-17)

**Branch:** `feat/doc-freshness-index-gate`
**Gap (confirmed in 1.20.0):** `skills/doc-quality-gate/SKILL.md` never names `INDEX.md`; `hooks/session-end-reminder` treats "any `.md` touched = docs remembered" (line ~26), so "code + new spec" passes without the cross-cutting trackers being checked.

### Task 1.1 — hook (developer, sonnet)
- `hooks/session-end-reminder`: add a branch — if the changeset contains a **new** `docs/specs/*.md` but `INDEX.md` (or project doc-map) is NOT among changed files → emit reminder (not necessarily block). Keep existing Case A–D logic intact. Must pass `bash -n`.

### Task 1.2 — skill prose (prompt-engineer, opus)
- `skills/doc-quality-gate/SKILL.md`: add `INDEX.md` (doc map) to per-class requirements — required when a new `docs/specs/` file is created. Reconsider feature-class "BACKLOG **or** CHANGELOG" → "BACKLOG **and** CHANGELOG" (decide with reviewer).
- Cross-link to `decision-context` / `doc-quality-gate` siblings; bump skill version.

### Task 1.3 — docs + version (developer, sonnet)
- CHANGELOG `## [1.21.0]`; version bumps; recurring checklist (README/INSTALL/llms-install if doc-flow described).

### Verify
- `bash -n hooks/session-end-reminder`; simulate a changeset with a new spec + untouched INDEX (reminder fires) and one with INDEX touched (silent).
- prompt-evaluator: gate triggers on "new spec, INDEX stale"; does NOT over-fire on a pure logic fix.
- code-reviewer + devils-advocate (parallel): false-positive risk, Case A–D regression.

---

## Phase 2 — Living plan-of-record ledger (Idea 2) → v1.22.0   ✅ SHIPPED (merged 1.22.0, 2026-06-17)

**Branch:** `feat/living-plan-ledger`
**Depends on:** Phase 1 merged (extends its gate).

### Task 2.1 — skill design + contract (agent-architect, opus)
- Design `skills/process/living-plan/SKILL.md`: matrix schema (package → TZ section → acceptance criterion → status → blocker/owner), rollup discipline, author/update/refresh lifecycle, scope trigger (**multi-package / contracted only**). Define the exact markdown contract + sentinel.

### Task 2.2 — skill prose + template (prompt-engineer, opus)
- Write `living-plan/SKILL.md` from the design; add `templates/IMPL-PLAN.md` with sentinel `> STATUS: TEMPLATE — not yet populated`.
- Wire references in `skills/process/writing-plans/SKILL.md` (author plan-of-record for contracted work) and `skills/process/executing-plans/SKILL.md` (flip criterion status on task close).

### Task 2.3 — validator + gate coupling (developer, sonnet)
- `scripts/check-plan.sh <project-dir>`: structural integrity (every criterion has a status, rollups consistent, no orphan blockers, sentinel gone once populated). `bash -n` clean; safe on missing file.
- Extend Phase-1 gate: a change closing a backlog/package item must also update the matching `IMPL-PLAN` criterion → reminder when stale.

### Task 2.4 — docs + version (developer, sonnet)
- CHANGELOG `## [1.22.0]`; version bumps; README roster (+1 skill); recurring checklist.

### Verify
- `check-plan.sh` against a stub (fail) and a populated fixture (pass).
- prompt-evaluator: living-plan triggers on a 2-package contracted task, NOT on a single feature.
- code-reviewer + devils-advocate (parallel): over-application risk, rollup-consistency edge cases.

---

## Phase 3 — Multi-instance coordination (Idea 3) → v1.23.0   ✅ SHIPPED as reduced v1 (registry + advisory claims + commit-lock + mailbox; ledger/gates/SQLite/fencing/enforcement-hook deferred to 3c)

**Branch:** `feat/multi-instance-coordination`
**Depends on:** Phase 2 (shared task ledger reused as the concurrency-safe ledger).
**Note:** largest phase; may itself split into 3a (registry + locks + lifecycle wiring) and 3b (mailbox + ledger + gates) at execution.

**Completeness principle (added after plan audit):** scripts + a protocol skill are NOT enough — without lifecycle wiring the whole thing is honor-system (the model must remember to read the skill and run the scripts; it won't). Phase 3 MUST wire the substrate into the plugin's hook lifecycle so registration, awareness, claim-enforcement, heartbeat, and deregistration happen automatically. All of it is gated behind an explicit opt-in so single-instance sessions pay zero cost.

### Task 3.0 — Enablement flag + lifecycle hook wiring (agent-architect + developer, opus) — THE BACKBONE
The mechanism that makes multi-instance automatic and enforced rather than documented. Nothing below fires unless `CLAUDE_SUBTEAMS_MULTI_INSTANCE=1` (or a settings equivalent) is set — single-instance sessions are completely unaffected.

1. **Opt-in gate:** `CLAUDE_SUBTEAMS_MULTI_INSTANCE` env flag. Every new hook branch and coord script no-ops when unset. Document in README + skill.
2. **SessionStart wiring** (`hooks/session-start`): when enabled — resolve the shared coord dir, create it if absent, `coord-register` this instance (id, pid, worktree, branch, heartbeat), `reap-dead` stale peers, and **inject awareness** into context: "multi-instance mode: you are instance `<id>`; N peers active: <roster>; follow the `multi-instance` skill — claim files before editing, communicate via mailbox." Without this injection the orchestrator never knows it is in a team.
3. **Claim ENFORCEMENT** — new `hooks/pre-tool-use-edit` on `PreToolUse` matcher `Edit|Write` (the plugin has no PreToolUse Edit/Write hook today): when enabled, look up the target file in the claim ledger; if claimed by *another live* instance → block (`exit 2`) with "file claimed by `<id>`; coordinate or wait", else auto-claim (or remind to claim) for this instance. This is the teeth behind "mark files busy"; covers subagent edits too (hooks are session-wide).
4. **Heartbeat refresh:** piggyback `coord-heartbeat` on the existing `UserPromptSubmit` and async `PostToolUse` hooks so an active-but-quiet instance is not reaped. (Hooks are event-driven, not timed — refresh must ride existing events.)
5. **Deregister + release on exit** (`hooks/session-end-reminder`, Stop): when enabled, `coord-release --all-mine` + `coord-deregister` (idempotent — Stop can fire repeatedly). flock-based locks auto-release on process death; file-based claims need this explicit path + heartbeat-reap as backstop.
6. **using-subteams reference:** add a short multi-instance subsection to the always-loaded meta-skill so the orchestrator knows the capability exists and when it activates.
7. **orchestrator-briefing:** note that in multi-instance mode, subagent briefs must state which files are claimed/off-limits.

### Task 3.1 — system design + contract (agent-architect, opus)
- Design the coordination substrate topology: presence/registry (§4.0 of spec), flock commit-lock, claim/lease, mailbox, heartbeat/reap. Define the on-disk layout, file schemas, and the exact script CLI contracts. Decide 3a/3b split.
- **Shared coord dir key:** derive from the COMMON repo, not the worktree — `~/.claude/subteams/<hash of $(git rev-parse --git-common-dir)>/` — so all worktrees of one repo share one registry/ledger. (A per-worktree path would split the team.)
- **Ledger write serialization:** every coord script that mutates the registry / claim ledger / mailbox MUST `flock` that file for its read-modify-write, or the coordination mechanism itself races.

### Task 3.2 — coord scripts (developer, sonnet)
- `scripts/coord-*.sh`: `register`, `roster`, `claim`, `release`, `send`, `recv`, `heartbeat`, `reap-dead` — bash + flock, portable, zero-dep. Each `bash -n` clean; crash-safe (flock auto-release); stale-instance reap by heartbeat TTL.
- Optional `scripts/coord-sqlite.*` backend (BEGIN IMMEDIATE, visibility-timeout claim) — gated behind "project already has SQLite."

### Task 3.3 — skill prose (prompt-engineer, opus)
- `skills/coordination/multi-instance/SKILL.md`: the per-instance protocol (register on start → claim before edit → commit under flock with `GIT_OPTIONAL_LOCKS=0` → send/recv via roster-addressed inbox → heartbeat → deregister). Front-load "claim before edit." State the **2–3 instance cap on ≤4 GB hosts** and the worktree-cleanup guard (`git status --porcelain`).
- Cross-link `using-git-worktrees`, `parallel-dispatch`.

### Task 3.5 — hooks-as-quality-gates + adversarial-debate recipe (prompt-engineer, opus)
- Add a portable hook mechanism (NOT the native `TaskCompleted`/`TeammateIdle`): a coord-side gate so a task cannot flip to `completed` until a review pass is recorded — `exit 2`-style block + feedback, wired to the plugin's `code-reviewer`/`devils-advocate`/`verification-gate`. Borrowed *design* from agent-teams hooks, reimplemented on our file-based ledger.
- Add an adversarial-debate recipe (competing-hypotheses teammates that try to disprove each other) as a documented coordination pattern in the multi-instance skill.

### Task 3.4 — docs + version (developer, sonnet)
- CHANGELOG `## [1.23.0]`; version bumps; README (+1 skill, new coordination capability); recurring checklist.

### Verify
- **Opt-in isolation:** with the flag UNSET, confirm every new hook branch and coord script no-ops — a normal single-instance session behaves byte-identically to 1.22.0 (no coord dir created, no awareness injected, no edit interference). This is the most important regression test.
- **Lifecycle wiring:** SessionStart in enabled mode creates the coord dir + registers + injects awareness; Stop deregisters + releases claims; heartbeat refreshes on prompt/tool events.
- **Claim enforcement:** the PreToolUse Edit|Write hook blocks an edit to a file claimed by another live instance and allows it once released/reaped; verify it also fires for a subagent's edit.
- Script-level: spin 2 mock instances sharing one coord dir (different worktrees of one repo → same `--git-common-dir` key); assert mutual exclusion (one claim wins), mailbox delivery, dead-instance reap, ledger-write serialization under concurrent claims.
- prompt-evaluator: protocol skill + awareness injection trigger on a multi-instance scenario, not on normal single-session work.
- code-reviewer + devils-advocate + adversarial-testing + (cross-model gpt critics if Codex available): race conditions in the ledger read-modify-write, advisory-lock cooperation gaps, the enabled-but-no-peers case, Stop firing repeatedly, and scope-creep toward a job-queue framework.

---

## Cross-cutting verify / review (every phase)

- `using-subteams` Section 6.5: prompt-engineer authors, prompt-evaluator validates before ship. Never ship an unevaluated prompt/skill.
- `verification-gate` before each merge — evidence (command output), not claims.
- Triple-review for Phase 2/3 (structural): code-reviewer + architecture-guard + devils-advocate in parallel.

## Risks & nuances

- **Hook false positives (Phase 1):** INDEX-stale reminder firing on doc-light changes. Mitigation: trigger only on *new* `docs/specs/*.md`, reminder not block.
- **Ledger staleness (Phase 2):** a drifting plan-of-record is worse than none. Validator + gate coupling are the defense.
- **Cooperative-only locks (Phase 3):** advisory locks don't stop a process that bypasses the protocol. The PreToolUse Edit|Write hook (Task 3.0.3) enforces claims *within* a participating Claude Code instance (covers orchestrator + subagents), but a non-Claude editor or a `--no-hooks` run is not bound. This is enforced-within-the-tool, not OS-level mandatory locking — state the boundary in the skill.
- **Opt-in or bust (Phase 3):** all coordination is gated behind `CLAUDE_SUBTEAMS_MULTI_INSTANCE`. The single-instance path must be provably unaffected (see Verify) — a coordination cost leaking into ordinary sessions would be a worse regression than the feature is worth.
- **Heartbeat liveness vs swap pauses (Phase 3):** on a loaded ≤4 GB host, a real instance can stall past its heartbeat TTL and be wrongly reaped. Keep TTL generous (e.g. ≥10 min) and, for correctness-critical claims, pair with a fencing token (spec §3.2) — do not reap aggressively.
- **Resource ceiling (Phase 3):** proven by the OOM during the research that produced this plan — the 2–3 instance cap is the real safety control on small hosts, not the algorithm.
- **Rollback (each phase):** `git checkout main && git branch -D feat/<phase>`; backup tag `backup/pre-<phase>-*`.
- **Plugin update after each phase:** `/plugin marketplace update articortex` → `/plugin update claude-subteams@articortex` → `/reload-plugins`; canonical tag `claude-subteams--vX.Y.Z`.
