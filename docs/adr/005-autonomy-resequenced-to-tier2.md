# ADR-005: Scoped autonomy re-sequenced to Tier 2, to be built on the Task Contract with structural enforcement

**Status:** accepted
**Date:** 2026-07-01

## Context

The Tier 1 draft included an autonomy mode: env flag `CLAUDE_SUBTEAMS_AUTONOMY`, non-blocking milestone checkpoints in `executing-plans`, self-classified failure classes, and blast-radius caps. Plan defense ran three independent critics (devils-advocate, architecture-guard, Codex cross-model). They converged on one root finding: every safety claim was backed only by prompt posture — the caps forced a *non-blocking* checkpoint (capping nothing, with no total-run budget), failure classes were self-assigned by the actor incentivized to continue, nothing executable read the env "gate" (the multi-instance precedent it cited IS hook-enforced), there was no re-hydration after compaction (the primary killer of long unattended runs), and the contract the run would sync against is written by the same agent (goalpost drift). Shipping that as "bounded autonomy" is the confidence theater the spec's non-negotiable #2 forbids.

## Decision

Autonomy moves to Tier 2 and is built **on top of** the canonical Task Contract (Invariant A) with structural, machine-checkable enforcement: write-once acceptance criteria with append-only revision notes; a diff-based scope gate (`git diff --name-only` vs declared scope — out-of-scope ⇒ `operator-decision-required` automatically); caps and a total-run budget that **block**; a non-fakeable checkpoint gate (command exit code, or rare Codex adversary anchored to written criteria); mandatory contract re-read after any compaction with fail-closed reversion to interactive if the grant record is not recoverable; a visible run record (grant text, scope, expiry) restated at every checkpoint; and a documented mid-run kill-switch. Tier 1 ships only the honesty invariant + rails delivery. Operator approved (option A).

## Consequences

- **Positive:** No autonomy semantics ship that the plugin cannot honestly enforce; manual-first stays intact (milestone pause untouched in 1.26.0). Tier 2 autonomy inherits a real spine instead of retrofitting one. The naming rule is recorded: without ALL structural controls, the feature must be called "assisted continuation", not autonomy.
- **Negative:** The operator's "work autonomously on command" need stays unmet for one more release cycle. Tier 2 scope grows (contract + autonomy together).
- **Neutral:** `executing-plans` and `hooks/` untouched in Tier 1; the design of the structural controls is fully specified in the spec §3 so Tier 2 starts from a reviewed blueprint.
