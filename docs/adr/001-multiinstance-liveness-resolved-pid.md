# ADR-001: Multi-instance liveness keys on the resolved long-lived pid, with heartbeat-TTL fallback

**Status:** accepted
**Date:** 2026-06-22

## Context

The v1 multi-instance substrate (1.23.0) decided instance liveness purely by `kill -0 <pid>`, where `<pid>` was the SessionStart hook's `$PPID`. On harnesses that run Claude via the Agent SDK / as a service (not the interactive CLI), `$PPID` is an ephemeral `sh -c`/bash shell that exits the instant the hook returns — so every instance was registered with a dead-on-arrival pid and reaped on the first `reap`/`roster`/`claim` pass. Result: `roster` always empty, `claim` always `exit 4`, multi-instance totally non-functional off the interactive CLI. The design spec (§3.2, §7.9, §7.0) had actually anticipated heartbeat-TTL liveness; the v1 *implementation* diverged to PID-only and documented it as intentional.

## Decision

Register the **resolved long-lived process pid** — walk up the process tree to the persistent `claude` ancestor (`_resolve_instance_pid`) and store it as `pid_trusted` — and make `_alive()` authoritative by `kill -0` for a trusted pid, falling back to a heartbeat TTL (`CLAUDE_SUBTEAMS_HEARTBEAT_TTL`, default 1800s) only when the real pid is unresolvable.

## Consequences

- **Positive:** Multi-instance works on SDK/service harnesses (the real `claude` pid is session-long and per-instance distinct). A quiet-but-alive instance is never wrongly reaped (its real process is alive), and a dead one is reaped immediately — no TTL wait, so `SessionEnd` cleanup is no longer load-bearing. The interactive-CLI case is unaffected (its pid was already good; resolution finds the same `claude` ancestor). Aligns implementation with the spec's original heartbeat-TTL intent. Closes the `pid=0` immortal-zombie hole (`kill -0 0` always succeeds) via a `pid > 0` guard.
- **Negative:** The TTL fallback (untrusted pid) reintroduces the spec §3.2 "bare TTL is unsafe for correctness locks" risk — an instance doing only non-edit work past the TTL can be reaped while alive, freeing its claims. This is bounded to harnesses where the `claude` ancestor cannot be resolved, and claims remain advisory; fencing tokens are still deferred. Liveness now depends on a process-name heuristic (`claude`/`claude-code`); a harness with a different persistent process name falls to the TTL path.
- **Neutral:** Registry entries gain a `pid_trusted` field (back-compatible — absent ⇒ `false` ⇒ TTL path). Deregistration moved from the per-turn `Stop` event to `SessionEnd` so claims survive across turns. Supersedes the "PID is authoritative, heartbeat is observability-only" stance of CHANGELOG 1.23.0.
