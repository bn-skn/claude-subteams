# ADR-010: Stack as a compared decision; ADR records alternatives

**Status:** accepted
**Date:** 2026-07-06

## Context

`brainstorming` (unchanged since 1.18.0) compared architectural *approaches* but treated the *stack* as a constraint to elicit ("what stack do you have"), never as a decision to compare — so a suboptimal stack got locked in silently on greenfield work. Separately, rejected options lived only in the ephemeral `decision-context` journal block; the durable ADR that `architecture-guard` reads as truth recorded only the chosen decision. A four-critic plan review (Claude + Codex/GPT, reviewers and devil's-advocates) confirmed both gaps and, applying the 1.28.0 audit verdict "subtract, don't add," cut the original five-change plan to these two.

## Decision

(C1) Make the stack a checklist-level *compared* decision in `brainstorming` — an observable **Stack Decision** block, recorded as an ADR via `adr-tracker` **decoupled** from the greenfield/structural Architecture Capture gate, with the stack ADR `proposed` until owner approval. (C2) Add an `Alternatives considered` section to the ADR contract across all four copies of the format.

## Alternatives considered

- **Spec template + mechanical spec gate (original C3/C4)** — rejected: a prose design doc is not load-bearing state (unlike plans / arch-docs, which are read mechanically), a gate on prose false-fails legitimately terse specs, and the structure already exists in the Spec Self-Review. Replaced by two self-review bullets — zero new files, zero new scripts.
- **De-dup interview rules across `brainstorming` and `using-subteams` §7 (original C5)** — rejected: skills load into context independently (no transclusion), and §7 runs in the Lightweight/Standard pipelines that skip `brainstorming` entirely, so a single source is unreachable at runtime. It is legitimate duplication under different load contexts; drift risk on six stable rules is near zero.
- **Route the stack decision through the existing Architecture Capture flow (initial C1 wording)** — rejected: it over-widens that flow's greenfield/structural scope guard onto logic-only work AND leaves the stack decision with nowhere to land in a non-greenfield project. Decoupled to a plain `adr-tracker` ADR instead, with the full `ARCHITECTURE.md`/`CONVENTIONS.md` population reserved for genuinely structural work.

## Consequences

- **Positive:** the stack becomes a conscious, comparable decision at the point of thinking; rejected options survive in the durable artifact `architecture-guard` trusts; the honesty invariant is now consistent across both ADR-creation paths — harmonizing Architecture Capture step 1 fixed a latent `accepted`-before-approval inconsistency, not just a stack one.
- **Negative:** `brainstorming` grows ~17 lines; the no-duplicate-stack-ADR behavior rests on prose recall across interview steps (mitigated by anti-duplicate guards placed at *both* the Stack Decision section and Architecture Capture step 1).
- **Neutral:** no mechanical enforcement — validation is instruction quality plus prompt-evaluator artifact predicates, deliberately not a gate (per the prose-vs-state distinction). C2 is mechanically inert to `check-arch-docs.sh`, which resolves ADR *links* and never parses ADR bodies.
