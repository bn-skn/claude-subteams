# ADR-002: Mailbox auto-delivery is count-only; peer content stays pull-only

**Status:** accepted
**Date:** 2026-06-22

## Context

The multi-instance mailbox is pull-based (`coord.sh recv`), so an orchestrator only sees peer messages if it remembers to poll — handoffs were missed. The obvious fix, injecting message content into context via a `UserPromptSubmit`/`SessionStart` hook's `additionalContext`, was prototyped and rejected in review: peer text is untrusted (the inbox is a plain file; `send --from` is unauthenticated; trust is transitive through whatever a peer ingested), so injecting it — especially framed as "act on them" — is a prompt-injection surface and contradicts the plugin's "hooks do not inject arbitrary content into the prompt" principle. Draining-to-deliver also destroyed messages before injection was confirmed (lossy on any harness that drops `additionalContext`).

## Decision

The `coord-notify` hook (UserPromptSubmit only, async:false) injects only a **count** of unread messages plus an instruction to pull them with `recv`, framed as untrusted data; it never injects message content and never clears the inbox. `recv` remains the explicit, lossless consume.

## Consequences

- **Positive:** No peer-controlled text ever enters context automatically — the injection surface is closed. Nothing is destroyed by the notifier, so a dropped notice costs at most one turn, never a message (read and clear are separable: `recv --count` peeks, `recv` consumes). The orchestrator reads peer messages as tool output it explicitly requested (correctly framed as data), and decides relevance itself. Respects the "SessionStart does not inject" invariant by staying off SessionStart. Newline-collapse on render stops a peer forging a fake `from:` header.
- **Negative:** One extra tool round-trip (the orchestrator must run `recv` after the nudge) versus content-in-context. Delivery still depends on the harness honoring `additionalContext` on `UserPromptSubmit`; if it does not, the operator falls back to running `recv` manually (the count nudge simply won't appear — no message is lost).
- **Neutral:** Adds a synchronous hook on every `UserPromptSubmit` (cheap: one `grep -c` line count under no lock). `recv` gains a non-destructive `--count` peek. Supersedes the rejected content-injection prototype (`coord-deliver`).
