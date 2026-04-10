---
name: adr-tracker
description: Tracks architectural decisions using lightweight MADR format. Creates, numbers, and stores ADRs in docs/adr/ for project-wide decision history.
sub-team: architecture
type: flexible
---

# ADR Tracker

## When to Apply

Use this skill when making architectural decisions that affect the project's structure, dependencies, or patterns. Flexible -- adapt the level of detail to the decision's impact.

## When to Create an ADR

ALWAYS create an ADR when:

1. Adding a new dependency (library, framework, service)
2. Changing a public API contract
3. Choosing between two or more viable patterns or approaches
4. Making a technology or framework decision
5. Deciding on a data storage strategy
6. Changing authentication or authorization approach
7. Introducing a new communication pattern (REST, gRPC, events)
8. Deciding to deviate from established conventions

You do NOT need an ADR for:

- Bug fixes
- Routine refactoring within existing patterns
- Minor dependency version updates (patch/minor)
- Implementation details that don't affect architecture

## ADR Format (Lightweight MADR)

```markdown
# ADR-NNN: Title

**Status:** proposed | accepted | superseded | deprecated
**Date:** YYYY-MM-DD

## Context

Why are we making this decision? What is the problem or opportunity?
(2-3 sentences maximum)

## Decision

What did we choose?
(1 sentence -- be specific)

## Consequences

What are the trade-offs?

- **Positive:** What we gain
- **Negative:** What we lose or accept as cost
- **Neutral:** What changes but is neither good nor bad
```

## Storage and Numbering

1. Store all ADRs in `docs/adr/` at the project root
2. Number sequentially: `docs/adr/001-use-postgresql.md`, `docs/adr/002-adopt-clean-architecture.md`
3. NEVER reuse a number, even if the ADR is superseded or deprecated
4. NEVER delete ADRs -- mark them as superseded or deprecated instead
5. When superseding, reference the new ADR: `**Status:** superseded by [ADR-005](005-switch-to-sqlite.md)`

## Status Lifecycle

```
proposed --> accepted --> [superseded | deprecated]
```

1. **proposed** -- Under discussion, not yet approved
2. **accepted** -- Approved and in effect
3. **superseded** -- Replaced by a newer decision (link to replacement)
4. **deprecated** -- No longer relevant (project moved on)

## ADR Creation Checklist

1. [ ] Determine the next sequential number
2. [ ] Write a clear, descriptive title (not "Database Decision" but "Use PostgreSQL for User Data")
3. [ ] Context explains the problem in 2-3 sentences
4. [ ] Decision is a single, specific sentence
5. [ ] Consequences list at least one positive and one negative trade-off
6. [ ] Status is set to "proposed" or "accepted"
7. [ ] Date is set to today
8. [ ] File saved in `docs/adr/` with correct numbering

## Example ADR

```markdown
# ADR-003: Use SQLite with WAL Mode for Local Data

**Status:** accepted
**Date:** 2026-04-10

## Context

The application needs a lightweight embedded database for local data storage.
We need concurrent read access during writes for the sync feature.
PostgreSQL is too heavy for a desktop application.

## Decision

Use SQLite with WAL (Write-Ahead Logging) mode for all local data storage.

## Consequences

- **Positive:** Zero configuration, single-file database, fast reads with WAL
- **Positive:** No external database process to manage
- **Negative:** Single-writer limitation -- must queue concurrent writes
- **Negative:** No built-in replication
- **Neutral:** Migration tooling works the same as with other SQL databases
```

## Reviewing ADRs

1. Review existing ADRs before proposing new architecture changes
2. Check for conflicting or superseded decisions
3. Reference related ADRs in the Context section when decisions build on each other
4. Periodically audit ADRs -- mark outdated ones as deprecated

## Red Flags

- Architectural decision made without an ADR -- create one retroactively
- ADR with vague context ("we needed something better") -- be specific about the problem
- ADR missing consequences -- every decision has trade-offs, document them
- Reusing or deleting ADR numbers -- numbers are permanent
- Multiple accepted ADRs that contradict each other -- supersede the older one
