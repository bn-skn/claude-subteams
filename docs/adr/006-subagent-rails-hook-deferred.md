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
