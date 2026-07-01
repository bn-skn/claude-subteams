# ADR-004: Honesty invariant lives in verification-gate + a compact per-agent block, not a new skill

**Status:** accepted
**Date:** 2026-07-01

## Context

Tier 1 (spec `docs/specs/2026-07-01-planning-autonomy-honesty-design.md`) introduces an honesty invariant: tool-failure honesty, claim provenance (TRUSTED / ATTRIBUTED / UNVERIFIED), anti-hedge, and a materiality threshold for when research is obligatory. The pattern is ported from the operator's battle-tested external CLAUDE.md honesty block (host-specifics stripped). Candidate homes: a new standalone `honesty-invariant` skill, CLAUDE.md-level guidance, or embedding in existing artifacts. Key constraint: subagents do not inherit session context or auto-load skills — a rule that lives only at orchestrator level never reaches delegated work. A prior multi-agent study also warned that a new standalone doctrine risks becoming a third parallel documentation system (the plugin's `adr-tracker` skill had already gone unused once).

## Decision

Authoritative detail lives in `verification-gate` (`## Claim Provenance` — namespaced against the pre-existing arch-doc "provenance" — and `## When a Tool or Command Fails`); `using-subteams` carries a short pointer (`### 4.1`, nested under Deep Research deliberately — promoting it to a top-level `##` would force renumbering sections 5–14 whose numbers are load-bearing cross-references in hooks and skills) plus one Red Flags row; every agent in `agents/*.md` carries an identical compact 4-bullet block right after `## Who You Are` (byte-uniformity asserted by grep+hash in the verification sweep); `orchestrator-briefing` embeds a 2-line distillation, scoped to briefs for generic (non-plugin) agents only, since plugin agents already carry the block in their prompts.

## Consequences

- **Positive:** The invariant survives delegation (the agent prompt is the only 100%-guaranteed channel). Detail is written once; pointers prevent copy-drift. Anti-hedge ships inside the same block, preventing the invariant from degrading into disclaimer spam. Materiality (4th bullet, added after devils-advocate review) closes the "label a material claim UNVERIFIED and feel compliant" hole for subagents that never see verification-gate.
- **Negative:** ~6 lines of constant token overhead in every agent context and a byte-uniformity maintenance obligation when adding agents (mitigated: sweep is count-agnostic, prose avoids hardcoding "16"). The provenance taxonomy is low-value for pure execution roles — accepted for uniformity.
- **Neutral:** researcher.md additionally maps its native confidence scale to claim provenance (they rate different dimensions). No new skill created; adr-tracker not revived.
