# ADR-007: Autonomy enforcement is a PreToolUse gate; its guarantee is drift-containment, not an adversarial sandbox

**Status:** accepted
**Date:** 2026-07-02

## Context

Tier 2 ships scoped autonomy (`CLAUDE_SUBTEAMS_AUTONOMY` + a per-grant run record). The plan-defense verdict (ADR-005) required the safety claim be backed by structure, not prompt posture. The first implementation put the check in `scripts/autonomy-check.sh` but left its *invocation* voluntary; a three-critic re-review (code-reviewer, security-auditor, Codex) found the hook was additionally dead-on-arrival (registered without its event argument), then, once wired, found the record-edit deny bypassable. Five parallel reviews across two rounds converged on one structural truth: **an agent that has the Bash tool can write any file on disk, including its own grant record — no in-repo mechanism can fully prevent that from within.**

## Decision

Enforcement is a blocking `PreToolUse` hook (`hooks/autonomy-gate`, matcher `Edit|Write|MultiEdit|NotebookEdit|Bash`, env-gated so it is inert when `CLAUDE_SUBTEAMS_AUTONOMY` is unset) that delegates scope/cap arithmetic to `scripts/autonomy-check.sh`. It structurally blocks, before the edit lands: out-of-scope or cap-exceeding writes by the file-writing tools (with canonical-path matching so `../`/relative/symlink spellings cannot dodge it), edits to the run record itself, and — best-effort, pattern-matched — Bash commands that reference the record. All non-zero exit codes mean STOP; freshness/session/expiry failures fail closed.

We accept a **named residual**: a determined agent can still rewrite its grant via a shell construction the pattern-match does not recognize (`python -c`, base64, variable indirection). We do NOT attempt to close this from inside the repo (it would require OS-level sandboxing outside the plugin's reach). Instead we bound the **claim** to what the structure delivers: **bounded autonomy contains an agent that DRIFTS off its granted scope — the common, non-adversarial failure mode — and is NOT a sandbox against an agent that deliberately jailbreaks its own leash via shell.** This honest scoping is recorded in the skill docs and CHANGELOG. (Operator chose this over the alternative — binding the grant to a harness-set env fingerprint the agent cannot forge — because the solo-operator threat is drift, not self-sabotage, and per-grant env ceremony is friction disproportionate to that threat. The fingerprint approach is left open as a Tier 3 hardening if adversary-resistance is ever needed.)

## Consequences

- **Positive:** The gate is real structure for the drift case — file-tool scope/cap violations and record edits are blocked before landing, verified by 142 adversarial tests including every path-aliasing and cwd-subdir bypass. The claim matches the mechanism, so the plugin's own honesty invariant is upheld rather than violated by an overclaim.
- **Negative:** Autonomy is not a security boundary against a malicious shell-equipped agent; an operator must not grant autonomy in a context where that is the threat. Stated plainly in `executing-plans` `## Autonomy Mode` and the CHANGELOG.
- **Neutral:** `autonomy-check.sh` (~420 lines) and `autonomy-gate` (~260 lines) exceed the 200-line guideline; accepted as cohesive single-responsibility security scripts with a documented Tier 3 split-trigger. The env-fingerprint path (Tier 3) would upgrade the claim to adversary-resistant at the cost of operator ceremony.

## Related
Commits 04aefc4 (impl), ea6bfbe + 4228743 (round-1 hardening), fix batch #2 (path canonicalization, cwd repo-root, NotebookEdit, best-effort Bash detection, LINES fix). Reviews: 5 agents × 2 rounds. Supersedes nothing; extends ADR-005's autonomy-on-contract decision with the enforcement mechanism and its honest threat-model boundary.
