# ADR-006: Rails delivery ships via the briefing channel; the SubagentStart hook is deferred with recorded constraints

**Status:** accepted
**Date:** 2026-07-01

## Context

Tier 1 needs every spawned subagent to receive the project rails (conventions/architecture docs, active plan). Two candidate channels: (1) a mandatory `Rails:` field in the orchestrator brief — guaranteed delivery, since the brief is the subagent's entire world; (2) a `SubagentStart` hook injecting `additionalContext`. Research (official hooks docs, 2026-07-01, CLI 2.1.197) confirmed the event exists and supports an agent-type matcher, but delivery of `additionalContext` into the *subagent's* context is not explicitly documented (the changelog grants additionalContext explicitly only to Stop/SubagentStop), and all three plan-defense critics flagged the hook as over-built for Tier 1: unconfirmed channel, redundant over the guaranteed floor, and a new every-subagent injection surface at odds with the plugin's own hook conservatism (`coord-notify` refuses to inject peer content; `session-start` is "minimal, no prompt injection").

## Decision

Tier 1 ships channel (1) only: mandatory `Rails:` brief field + a `Rails read:` acknowledgment line in the subagent output contract (short quote of the applied constraint + diff file:line — an attention prime and spot-check anchor, honestly documented as NOT a guarantee). The hook is deferred to Tier 2 behind four recorded constraints: register `"async": false` (async hooks' additionalContext is ignored — coord-notify precedent), matcher `""` not `"*"` (house style; `*` is invalid regex in some harness versions), register only after a sentinel delivery test passes on the operator's CLI version, and inject only static plugin-authored text/paths — never project-authored file contents (prompt-injection hygiene).

## Consequences

- **Positive:** Tier 1 rails delivery works today with zero new attack surface and no hooks.json changes; the future hook, if built, starts from pre-reviewed constraints instead of rediscovering them.
- **Negative:** Rails delivery depends on orchestrator discipline (the brief field) until the hook lands; a rushed brief can omit it. The `Rails read:` ack is fakeable — accepted and documented as posture-tier.
- **Neutral:** In repos without conventions/architecture docs the field degrades gracefully ("when they exist"); the rails *content* artifact itself is Tier 2 work (project rails as a first-class once-per-project document).

## Amendment — 2026-07-02 (Tier 2): sentinel passed, hook built

The gating condition named above (a `SubagentStart` sentinel delivery test) was run on CLI **2.1.197** and **passed**: a `SubagentStart` command-type hook returning `hookSpecificOutput.additionalContext` was received verbatim inside the spawned subagent (a distinctive token round-tripped back). Confirmed twice — first with a throwaway fixture hook, then with the shipped `hooks/subagent-rails` wired through a real `settings.json` (the shipped hook's static rails+honesty text appeared in the subagent's context). So the doc-ambiguity ("additionalContext on SubagentStart not explicitly documented") is resolved empirically in favour of delivery.

The hook therefore ships in Tier 2 under all four recorded constraints: `"async": false`, matcher `""`, command carries the `SubagentStart` event arg (the wiring bug that made it inert was caught in review and fixed — see ADR-007), and it injects only static plugin-authored text (never project file contents). Honest limitation not closed by the sentinel: the raw SubagentStart input-payload keys (`agent_id`/`agent_type` presence/shape on 2.1.197) were **not** separately enumerated — delivery of additionalContext is confirmed, per-field input schema is not; the hook does not depend on those input fields, so this is recorded as a known-unverified detail, not a blocker.
