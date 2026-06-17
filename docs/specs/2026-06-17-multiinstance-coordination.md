# Multi-Instance Coordination & Async Communication — Design Specification

**Date:** 2026-06-17
**Status:** Draft — for approval (forward-looking; likely a v-next capability)
**Author:** Bogdan + Claude Opus 4.8
**Idea ref:** Idea 3 of the 3-idea modernization set
**Research:** synthesized from deep-research run wf_c8320ebf-110 (42 agents; sources cited inline below). Synthesis assembled by orchestrator (workflow's own synthesize stage did not run).

---

## 1. Problem & framing

Today claude-subteams orchestrates **within one Claude Code process**: an orchestrator dispatches subagents via the `Agent`/`Workflow` tools, all in a single process and (optionally) git worktrees.

Idea 3 is a different topology: **N separate, identical `claude` CLI processes** running on **one Linux machine** (the VPS: 2 vCPU, 3.7 GB RAM), working **the same git repository** in parallel, asynchronously. They must (1) not corrupt each other's work, (2) know when a file/task is "busy" (mutual exclusion), and (3) communicate asynchronously (status, handoff "module X is ready").

**Critical constraint a plugin cannot cross:** the plugin cannot spawn or supervise OS processes. A human (or an outer launcher) starts the N instances. What the plugin *can* provide is the **coordination substrate**: skills (protocol), helper scripts (claim/release/send/recv/heartbeat), a schema, and the doc-discipline that makes parallel instances safe. Each instance's orchestrator follows the protocol.

**Hard environmental lesson (lived during this very research):** the deep-research workflow was OOM-killed on this box when a verify phase fanned out to 75 concurrent agents (RAM hit 977 MB free, swap 75%). Conclusion baked into this design: **on a 2 vCPU / 3.7 GB host, keep concurrent instances small (2–3), coordination lightweight, and never introduce a heavy broker (Redis/NATS).**

## 2. Scope

**In scope:** a portable coordination protocol + helper scripts + skills so that several human-launched Claude Code instances on one machine/one repo can isolate file work, claim tasks/modules, detect dead peers, and exchange durable async messages.

**Out of scope:** spawning/supervising instances (human/launcher job); distributed/multi-machine coordination (explicitly excluded — single host only); replacing the existing in-process `Agent`/`Workflow` orchestration (this is additive, for cross-process).

## 3. Research findings (what the design rests on)

### 3.1 File isolation — git worktrees, with sharp edges

- **Worktrees are the established primitive** for parallel agents on one repo (ccswarm v0.9.1, Claude Code agent-teams, Augment Code, MindStudio). Per-worktree index/HEAD; shared `.git` object store and refs.
- **Verified pitfall (high confidence, primary `anthropics/claude-code #55724`):** concurrent **commits** collide on **shared** `.git` resources — `refs/`, `packed-refs`, object packing. Measured: **8/13** parallel agents failed on lock contention; intermittent at 5, near-certain at 10+.
- **Verifier correction (a claim was refuted 2/3):** the contention is NOT on `index.lock` (that is per-worktree and does not collide). Attributing collisions to `index.lock` is a factual error; the real shared locks are refs/packed-refs/object-pack. Design must speak of *those*.
- **Stale lock from polling (`#57102`):** background read-only git polling leaves 0-byte `index.lock` files. Mitigation: **`GIT_OPTIONAL_LOCKS=0`** for every instance.
- **No same-file collision warning** across worktrees — conflict is merely deferred to merge (Augment, Anthropic coordination-patterns blog). An explicit file/module mutual-exclusion layer is still required up front.
- **Cleanup hazard (contested):** `#55724` reported auto-cleanup destroying uncommitted work; one verifier refuted it citing official docs (current default *preserves* worktrees with uncommitted changes, needs `--force`). Treat as version-dependent — guard cleanup with `git status --porcelain` regardless.

### 3.2 Mutual exclusion — flock primary

- **`flock(2)`** (primary, man7.org/Kerrisk): best one-machine primitive. **Kernel auto-releases on crash** (fd close) → no stale locks by construction. Advisory (fine: our own cooperating instances). Idiom `exec 200>lock; flock 200`. `-w` for bounded acquisition.
- **O_EXCL/mkdir lockfiles:** atomic but require PID + liveness check or a dead holder locks forever — the exact gravel flock avoids.
- **lease/TTL + fencing tokens** (Kleppmann): needed only against "hung but not dead." On this box GC/swap STW pauses are real, so a bare TTL without a monotonic **fencing token** is unsafe for correctness-critical writes (a paused agent can wake past expiry and clobber). Efficiency locks (don't-duplicate-work) → plain TTL fine; correctness locks (shared state, git index) → fencing.
- **SQLite as broker** (optional): zero-new-dep *only where SQLite already exists*. `BEGIN IMMEDIATE` mandatory or read→write upgrade yields instant `SQLITE_BUSY` despite busy_timeout (Bert Hubert).

### 3.3 Async communication

- **Durable mailbox** is the requirement for "module X ready" handoff. Two viable portable forms:
  - **Per-agent JSON inbox files** (maildir-style) — exactly what Claude Code agent-teams (`~/.claude/teams/.../inboxes/{agent}.json`) and the Swarm gist do. Push-style, file-based, zero-dep.
  - **SQLite mailbox table** — durable, atomic claim via `BEGIN IMMEDIATE`, read-from-offset by status; best *if SQLite is already in the stack*.
- **Append-only JSONL multi-writer log — gotcha (corroborated 3×: nullprogram/Wellons, Oz Solomon, Siebenmann):** POSIX does NOT guarantee atomic appends for regular files across processes; safe only below ~PIPE_BUF (≈4 KB on Linux). Fine as a **single-writer** event journal; unsafe as a multi-writer channel.
- **FIFO / Unix sockets:** ephemeral — good for live status streaming, no durability or read-from-offset → unsuitable as the durable handoff channel on their own.

### 3.4 SQLite WAL as coordination DB / queue (optional backend)

- Single-writer persists even under WAL; design for short transactions. Working triad: **WAL + busy_timeout + short transactions** (busy_timeout alone insufficient).
- No `SKIP LOCKED` → claim via a **visibility-timeout column** + status machine (`pending/processing/done/failed`); TTL-lease auto-requeues dead workers' jobs (dev.to SQLiteQ, Jason Gorman).
- No FIFO fairness in lock contention → possible starvation under load (SkyPilot).
- Capacity is a non-issue at our scale: Gorman 12 workers / 0 busy errors; SQLiteQ ~20k ops/s, 49 µs/op.

### 3.5 Coordination patterns

- **Claude Code agent-teams (primary docs):** files under `~/.claude/teams/` + `~/.claude/tasks/`; task claim via **OS file locking**; **Mailbox push** delivery; **single fixed leader, no election**; 3-state shared task list with deps + auto-unblock. Note: repo isolation is punted to worktrees; **no automatic file-level lock for code edits** ("two teammates editing one file → overwrites").
- **ccswarm:** worktree isolation + append-only NDJSON audit; DAG orchestration; synchronous quorum ("Sangha").
- **Swarm gist:** per-agent JSON inbox; task-ownership claim; **5-min heartbeat** for dead detection; auto-unblock deps.
- **Anthropic coordination-patterns blog:** vocabulary — Agent Teams (shared-queue claim) / Shared State / Message Bus; warns shared-state loops need first-class termination conditions.
- **Leader election: not needed on one machine** — fixed leader, or "first to take the commit-lock." Heartbeat needed; fencing for idempotent critical writes.

## 4. Recommended architecture

A **file-based-primary** substrate (matches the plugin's portable, zero-dependency ethos and mirrors Anthropic's own agent-teams), with an **optional SQLite backend** for projects that already run SQLite (e.g. claudebot):

0. **Presence / registry (membership) — precondition for everything below.** Communication is impossible without peer awareness. On startup each instance **registers** itself: writes `<coord>/instances/<id>.json` carrying `{id, pid, worktree, branch, role, started_at, heartbeat}`. The directory is a **live roster** — any instance reads it to learn who is online (heartbeat fresh), whom to address a message to (inboxes are keyed by `id`), and who owns which task. A stale-heartbeat instance is reaped from the roster and its claims requeued. This is exactly how Claude Code agent-teams works (files keyed by session-id under `~/.claude/teams/`). Without this layer, the mailbox (§5) and task-claim (§4) have no addressable peers.

1. **Isolation:** one git worktree per instance + `GIT_OPTIONAL_LOCKS=0` exported for all.
2. **Commit serialization:** a single global **commit-lock via `flock`** on `<coord>/commit.lock` (crash-safe) — eliminates the §3.1 ref/pack contention. Fallback: retry + exponential backoff + jitter.
3. **Mutual exclusion (files/modules/tasks):** `flock`-based claim per resource for efficiency locks; for correctness-critical shared state, a lease with a monotonic **fencing token** stored in the coordination dir.
4. **Task ledger:** a shared 3-state task list (this is where Idea 2's plan-of-record meets Idea 3 — same ledger, now concurrency-safe), claim-by-status with atomic claim (flock around the write, or `BEGIN IMMEDIATE` on the SQLite backend).
5. **Mailbox:** per-instance JSON inbox files (maildir-style), durable; messages = status + handoff events ("module X ready"). SQLite mailbox table as the alternative backend.
6. **Liveness:** heartbeat timestamp per instance; dead instance detected by TTL (~5 min, per Swarm gist), its claims auto-requeued, its commit-lock force-reclaimed (flock already auto-releases on process death).
7. **Event journal (optional):** single-writer append-only JSONL for human-readable audit only — NOT a multi-writer channel.

### 4.1 Plugin deliverables (sketch — detailed in the impl plan after approval)

- `skills/coordination/multi-instance/SKILL.md` — the protocol each instance's orchestrator follows (register on start, claim before edit, commit under lock, send/recv mailbox, heartbeat, deregister on exit).
- `scripts/coord-*.sh` — `register`, `roster`, `claim`, `release`, `send`, `recv`, `heartbeat`, `reap-dead` (bash + flock; portable, zero-dep).
- Optional `scripts/coord-sqlite.*` backend for SQLite projects.
- Schema doc for the coordination directory layout (`<repo>/.subteams-coord/` or `~/.claude/subteams/<repo-hash>/`).

## 5. Key decisions — RESOLVED (2026-06-17, owner approval)

1. **Backend:** ✅ **file-based primary (flock + JSON inbox), SQLite optional.** Portable, zero-dep; SQLite backend offered only for projects already running it (claudebot).
2. **Coordination dir location:** out-of-repo `~/.claude/subteams/<repo-hash>/` (keeps the working tree clean, survives worktree removal, matches agent-teams). *(recommendation stands; confirm at impl.)*
3. **Concurrency ceiling:** ✅ hard-cap guidance **2–3 instances on a ≤4 GB host** (the OOM lesson), surfaced in the skill. Larger only on bigger hosts.
4. **Sequencing:** ✅ **implement after Ideas 1 + 2** (order 1 → 2 → 3, each its own pipeline cycle).
5. **Presence/registry:** ✅ **required component** (added §4.0) — peer awareness is a precondition for communication, per owner's design note.
6. **Build-our-own vs native agent-teams:** ✅ **build our own portable substrate; do NOT depend on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.** Rationale (owner decision 2026-06-17): the plugin must run on **other harnesses** in future; coupling Idea 3 to a Claude-Code-only experimental feature is incompatible with that goal, and avoids its churn/limitations (no teammate resume, status lag, settings + tmux/iTerm2 deps). Claude Code's agent-teams is used as a **design reference** (registry/members, push mailbox, file-locked 3-state task list, worktree-lock-while-running, hooks-as-gates) — reimplemented on portable OS primitives (flock + JSON files + git worktrees). Caveat: the plugin's *intra-instance* orchestration still uses the Claude-Code `Agent` tool today; full multi-harness portability is a separate larger effort — Idea 3's coordination layer being portable-by-design adds no new coupling.
7. **Hooks-as-quality-gates:** ✅ included in this phase (Idea 3) — wire task-completion / idle gates to the plugin's reviewers (`exit 2` blocks closing a task until review passes). See impl plan Phase 3.

## 6. Open questions

- **Peer messaging shape:** with the registry (§4.0) in place, inboxes are addressable per-instance, so directed messages are possible. Default to **addressed fire-and-forget** (A posts to B's inbox or to a topic; B picks up async) — covers status + handoff + "is anyone working on X?" without the complexity of synchronous request/response. Synchronous A-asks-B-and-waits is deferred unless a concrete need appears (it risks deadlock on a 2-vCPU box).
- Should the commit-lock be **global** (one writer to `.git` at a time) or **per-ref**? Global is simpler and safe at 2–3 instances; per-ref only matters at higher concurrency we are explicitly avoiding.

## 7. Relationship to other ideas

- **Idea 2 (living plan):** the shared task ledger is the *same artifact* — single-instance it is markdown-as-truth; multi-instance it becomes the concurrency-safe ledger here, with markdown rendered from it. The schemas are designed to be the same matrix.
- **Idea 1 (doc-freshness):** unchanged; the freshness gate runs per-instance like any other.

## 8. Risks & nuances

- **Plugin can't enforce process discipline:** instances that ignore the protocol (edit without claiming, commit without the lock) still corrupt state. The substrate is cooperative (advisory locks). Mitigation: make the skill protocol unambiguous and front-load "claim before edit."
- **Resource exhaustion is the real ceiling**, not the algorithm — proven by the OOM during this research. The concurrency cap (§5.3) is the primary safety control on small hosts.
- **Contested cleanup claim** (§3.1) — guard worktree removal with `git status --porcelain` regardless of version.
- **Append-only JSONL trap** (§3.3) — never let two instances write one log; single-writer journal only.
- **Scope creep toward a job-queue framework:** resist. This is "a few cooperating CLIs on one box," not a distributed task system. If a project needs that, it has outgrown the plugin.
