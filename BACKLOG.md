# Backlog

## In Progress
- [x] Fire test on claudebot — real development task with plugin active

## Next Up
- [ ] Polish remaining 41 skills iteratively (prioritize by usage frequency)
- [ ] Replace claudebot CLAUDE.md methodology section (120 lines) with plugin snippet (6 lines)
- [ ] Enable subteams globally, disable superpowers
- [ ] Add CONVENTIONS.md to claudebot project

## Audit follow-ups (v1.27.0 health audit — 2026-07-02, mostly closed in 1.28.0)
Pre-existing / deferred items surfaced by the 9-agent + Codex audit and the 1.28.0 review. None block; filed so they are not lost. Do these BEFORE adding new capability (audit verdict: "next step is subtraction and fixing, not adding").
- [ ] **coord.sh: unchecked sequential `_jq_write` in a locked block** (e.g. `cmd_deregister`, `_reap_locked`). Under `set -uo pipefail` (no `-e`) a first-call failure still runs the second, and the subshell's exit reflects only the last command — deregister can report success while the instance was never removed. Low likelihood (needs JSON corruption / jq-or-disk failure); impact is stale coordination state, not a scope/cap bypass.
- [ ] **autonomy-check.sh single-writer check doesn't require SELF in the roster.** An empty roster passes vacuously; it only rejects OTHER ids. Depends on whether `coord.sh register` is reliably invoked at session start — decide whether "self must be present" should be required. Fails closed if the id convention ever diverges (safe direction), so not urgent.
- [ ] **coord.sh `recv --count` peek reads the inbox without the per-inbox lock** — can report a transiently stale count under a concurrent send. By design (non-destructive throttle peek), flagged for completeness.
- [ ] **autonomy-check.sh: small-valid + oversized plan both in `docs/plans/active/`** → the oversized file is silently ignored (its content never read). Cannot widen scope (fields never parsed), so not an escalation vector; masked-ambiguity edge case.
- [ ] **AC3 transient `.git/index.lock` halt** — a concurrent commit's lock can make `git diff` fail → fail-closed exit 4 stops a legitimate autonomous run. Accepted for 1.28.0 (asymmetry favors a re-invocation over an off-cap run). Reconsider a single bounded retry if it bites in practice.
- [ ] **hooks.json unquoted `${CLAUDE_PLUGIN_ROOT}` command path** — accepted-residual (install paths under `~/.claude/plugins/` have no spaces). Quote the path segment only after confirming the harness shell-executes the `command` field.
- [x] **session-end-reminder `systemMessage` rendering** — RESOLVED 2026-07-05: pinned against the official hooks docs — `systemMessage` is operator-only, the model never saw the 1.28.0 reminder. Redesigned as hybrid advisory (`additionalContext` to the model + `systemMessage` to the operator), fire-once per session (v1.29.0, ADR-009).
- [ ] **Prune maintenance surface** (audit cut-list, lower priority than the above): review the plan-cluster (writing-plans/living-plan/executing-plans/subagent-driven-dev) and the 7-skill meta-engineering cluster for genuine duplication; extract the honesty invariant (16 byte-identical copies) into a shared snippet if the agent format supports injection. Niche skills (mobile/i18n/data-engineering/accessibility) — KEEP if publishing to marketplace, prune only if plugin stays claudebot-only. Operator decision.

## Ideas

- **pre-commit-gate: false-positive matcher** — a non-echo-leading command containing literal `git commit` inside a string (`make build && echo "then git commit"`) passes the top filter; with staged unreviewed code it would block a harmless command. Pre-existing class (review F4, 1.33); fix = match `git commit` only as the statement's command position, not substring.
- **Stack Decision observability (follow-up to v1.31.0).** C1 governs orchestrator behavior through prose, with no mechanical enforcement (deliberate — prose vs load-bearing state). Watch live brainstorms: does the Stack Decision block actually appear when the stack is a live decision, and does it stay out of trivial tasks (no ceremony)? If it under-fires or over-fires in practice, add a **non-blocking** telemetry tier (warning-only: flag an empty Stack Decision on a greenfield task, or a missing ADR `Alternatives considered`) — a middle rung below a hard gate, so no false-fail risk. Deferred as YAGNI until there is evidence it bites. Raised by the GPT devil's-advocate in the 1.31.0 plan review (the "prose changes behavior, but you can't tell behavior changed from prompt-reads-better" critique).
- **Architecture-doc tripwire at read time (follow-up to v1.18.0).** The arch-capture gate (Rule 24) only fires in the Full+Architecture pipeline. A greenfield "just do it" routes to Lightweight/Standard, skips brainstorming, and ships a stub `ARCHITECTURE.md` with no gate — then a later session's `architecture-guard` reads the unpopulated template as truth (deferred empty-truth). Consider: `architecture-guard` (or the session-start hook) flags when it is about to treat a stub arch doc (sentinel still present) as ground truth.
- Publish to Claude Code plugin marketplace (when stable)
- Add skill manifest to plugin.json for better discovery
- Merge overlapping skills (orchestrator-briefing + subagent-prompt-design + agent-engineering → one skill)
- Add metrics collection (bugs caught, review findings, tokens consumed)
- External reviewer integration (Codex, Gemini)
- Hookify integration — auto-generate hooks from plugin rules

## Done
- [x] **Conscious stack-selection + ADR alternatives** — SHIPPED 2026-07-06 as v1.31.0 (ADR-010). Stack became a *compared* decision in `brainstorming` (Stack Decision block, ADR capture decoupled from Architecture Capture, proposed→accepted), and `Alternatives considered` was added across the ADR contract. Scope honesty: this is the surviving 2 of the original 5-item "strengthen interviewing / stack / spec-assembly" vision — a plan review cut spec-template + spec-gate + interview-rule dedup with reasons ("subtract, not add"; specs are prose not load-bearing state; skills load independently so a single-source dedup is unreachable). Those are REJECTED, not pending — do not reopen. Broad interview-depth and a full spec-assembly flow into `writing-plans` were consciously left un-built.
- [x] Design specification (29 sections, 5 review rounds) — 2026-04-10
- [x] Implementation v1.0 (46 skills, 9 agents, 6 hooks) — 2026-04-10
- [x] 3 rounds QA review + fixes — 2026-04-10
- [x] Polish 5 key skills to professional quality — 2026-04-10
- [x] Full audit by fresh-eyes reviewer — 2026-04-11
- [x] Audit fixes (visual-companion, conventions, README activation) — 2026-04-11
- [x] Published to GitHub: github.com/bn-skn/claude-subteams — 2026-04-10

## Recurring
- [ ] On version bump: verify README.md, INSTALL.md, templates/claudemd-snippet.md reflect current agent count, version, and features
