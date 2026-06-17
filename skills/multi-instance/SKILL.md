---
name: multi-instance
description: "Protocol for coordinating several Claude Code instances working one git repo on one machine — claim files before editing, commit under a lock, message peers. Opt-in via CLAUDE_SUBTEAMS_MULTI_INSTANCE; portable (not Claude Code agent-teams)."
---

# Multi-Instance Coordination

## 1. When this applies

Only when **several identical Claude Code instances run on ONE machine against ONE git repo** (each ideally in its own git worktree) AND the opt-in flag `CLAUDE_SUBTEAMS_MULTI_INSTANCE=1` is set. If you are a single session, this skill is irrelevant — ignore it.

You will know multi-instance mode is active because the SessionStart hook injects a line: `[subteams:multi-instance] Active — you are instance '<id>'; N live instance(s)`. That `<id>` (first 8 chars of the session id) is **your instance identity** for every command below.

This substrate is **portable and deliberately NOT Claude Code's native agent-teams** — it works on any harness with a shell, filesystem, and git. It is file-based (flock + JSON), zero new dependencies beyond `jq`.

**Hard limit:** on a ≤4 GB host, run **2–3 instances**, not more. Each is a full Claude process; more will exhaust RAM (this was learned the hard way). This is a coordination tool, not a job-queue framework.

## 2. What happens automatically (via hooks)

When the flag is on, the plugin's hooks handle lifecycle for you:

- **SessionStart** — registers your instance, reaps dead peers, injects the roster + this protocol into your context.
- **UserPromptSubmit / PostToolUse** — refresh your heartbeat (liveness).
- **Stop** — deregisters you and releases your claims (best-effort; a crash is still cleaned up by PID-based reap when a peer next runs).

You do NOT manage registration or heartbeat manually. You DO manage **claims, commits, and messages** (Section 3).

## 3. The protocol you must follow

All commands: `scripts/coord.sh <cmd>` (resolve the path from `${CLAUDE_PLUGIN_ROOT}` or the repo). Your `--id` is the instance id from the awareness line.

1. **Claim a file before editing it.** `coord.sh claim --id <you> <path>` — exit 0 = yours, exit 3 = held by a live peer (do NOT edit it; pick other work or coordinate via the mailbox). Claims are **advisory**: they bind cooperating instances, not `--no-hooks` runs or external editors. Honor them.
2. **Partition work by file/module up front.** Worktrees defer same-file conflicts to merge, not prevent them. The reliable rule is the old one: each instance owns a distinct set of files. Claims make that ownership visible and checkable.
3. **Release when done with a file.** `coord.sh release --id <you> <path>` (or `--all` at the end of a work unit) so peers can pick it up. Do not sit on a claim for a file you have finished.
4. **Commit under the commit-lock.** Concurrent commits across worktrees collide on shared `.git` refs/packed-refs. Wrap commits: `coord.sh commit-lock -- git commit -m "…"`. Also `export GIT_OPTIONAL_LOCKS=0` (the SessionStart tip) to avoid stale `index.lock` from background polling.
5. **Communicate via the mailbox** (fire-and-forget, addressed): `coord.sh send --from <you> --to <peer> "module X ready"`; read yours with `coord.sh recv --id <you>` (reading clears it). Use it for handoffs and status — "I finished the API, the client work is unblocked."
6. **Check the roster** to see who is live and what they hold: `coord.sh roster` and `coord.sh claims`.

## 4. Dispatching subagents in multi-instance mode

Your subagents (Agent tool) edit files within YOUR instance. Before dispatching a subagent to edit files, **claim those files yourself first**, and state in the brief (per `orchestrator-briefing`) which files are claimed for it. A subagent cannot meaningfully claim on its own — you own the claims for work you delegate.

## 5. Liveness & failure model

- Liveness is authoritative by **PID** on this single host (`kill -0`) plus worktree existence: a dead process (or a removed worktree) is reaped by the next peer's `roster`/`claim`/`reap`, freeing its claims immediately. A PID-alive instance is **never** reaped for being quiet — a real instance can sit in a long tool call without harm.
- Heartbeat is recorded (refreshed on prompt/edit events) for observability and reserved for future use; it is **not** a reap trigger. PID reuse (a different live process landing on a recycled pid) is an accepted rare gap on a single host with 2-3 long-lived instances.
- `flock`-based locks (the commit-lock) auto-release on process death — crash-safe by construction.

## 6. Scope boundaries (what this is NOT)

Deferred by design (do not assume these exist): a shared task ledger / job queue, hooks-as-quality-gates, a SQLite backend, fencing tokens. v1 is registry + advisory file claims + commit-lock + mailbox + heartbeat. If you find yourself wanting a distributed task queue for 2–3 cooperating CLIs, stop — that is the scope creep this design refuses.

## 7. Critical Rules

1. Claim a file (exit 0) BEFORE editing it; never edit a file a live peer has claimed (exit 3).
2. Commit only via `coord.sh commit-lock -- git commit …`; export `GIT_OPTIONAL_LOCKS=0`.
3. Release claims when done with a file; release `--all` at the end of a work unit.
4. Respect the 2–3 instance cap on small hosts.
5. Claims are advisory — they coordinate cooperating instances, they do not enforce against external writers. Do not treat "claimed" as "physically locked."
6. Pre-claim files before dispatching a subagent to edit them.

## 8. Cross-References

- `using-git-worktrees` — one worktree per instance (the file-isolation layer beneath this).
- `orchestrator-briefing` — state claimed/off-limits files in subagent briefs.
- `parallel-dispatch` — in-process parallelism (subagents) vs cross-process (this skill).
- Spec: `docs/specs/2026-06-17-multiinstance-coordination.md`; substrate: `scripts/coord.sh`.
