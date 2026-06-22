# ADR-003: Autonomous mailbox delivery via PostToolUse notify + polling discipline

**Status:** accepted
**Date:** 2026-06-22

## Context

The 1.24.0 mailbox notifier ([ADR-002](002-mailbox-notify-count-only.md)) fired only on `UserPromptSubmit`, which exists only in interactive sessions. Agents running autonomously for hours have no human prompts, so they would never be notified of peer messages — the very scenario multi-instance coordination targets. A background push channel was rejected as out of scope (no broker, 2-3 instances).

## Decision

Notify on `PostToolUse` as well (autonomous agents call tools constantly), throttled to one notice per newly-arrived message via a per-instance `notify/<id>.last` timestamp marker (`coord.sh notify-due`), and make protocol-level polling the backbone: the skill mandates `recv`/`roster` at coordination checkpoints (before claim, after a work unit, before the commit-lock) and sending a deliberate handoff when a unit unblocks a peer.

## Consequences

- **Positive:** Autonomous, promptless agents now learn of peer messages during normal tool use, without a background watcher or broker. Throttle prevents per-tool-call spam (one notice per new message, robust across `recv` clears because the marker keys on the newest message timestamp). Subagents are skipped (`agent_id` present → no notice) so only the orchestrator is nudged. Polling discipline guarantees correctness even if a notice is missed — hooks are an assist, not the contract.
- **Negative:** A synchronous hook now runs on every `PostToolUse` (cheap: a no-lock line count, then `notify-due` only when due). Notice granularity is one second — a burst of messages to the same recipient within one wall-clock second notifies once (acceptable: `recv` is the source of truth and returns all of them; the notice is only a doorbell). Still depends on the harness honoring `additionalContext` on `PostToolUse`.
- **Neutral:** Adds `coord.sh notify-due` and a `notify/` state dir. UserPromptSubmit keeps the always-show count (interactive reminders are infrequent and want reliability); PostToolUse uses the throttle. Extends, does not supersede, ADR-002.
