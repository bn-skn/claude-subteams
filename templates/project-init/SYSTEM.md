# System: <PROJECT_NAME>

## Layer 1 — System Description

### Overview

<!-- What the system does in 2-3 sentences. Who uses it and what problem it solves. -->

**Goal:** <PROJECT_GOAL>
**Domain:** <DOMAIN>
**Stack:** <STACK>

### Components

| Component | Layer | Purpose |
|-----------|-------|---------|
| `<ComponentName>` | presentation / application / domain / infrastructure | What it does |

### Data Flow

1. <!-- Step 1 -->
2. <!-- Step 2 -->
3. <!-- Step 3 -->

### External Dependencies

| Dependency | Purpose | Version |
|------------|---------|---------|
| <!-- lib --> | <!-- why --> | <!-- x.y.z --> |

---

## Layer 2 — Decisions Journal

Append-only. Newest entry at the top.
Each entry uses the decision-context block format (see `decision-context` skill).
Write a block at end of work whenever any of these touched: schema/data, security, performance, external integrations, pattern shift, risky refactor, new dependency, algorithm choice.
Skip for cosmetic changes, typos, patch-version bumps, doc edits.

### Format

```
**Decision:** one line — what was done.
**Why:** the problem this solves. If reproducible, how to reproduce.
**Alternatives:** what else was considered and why it was rejected. If there was no alternative, say "only option, because …".
**Risks / weak spots:** what can break, under what conditions. What to monitor. How to roll back.
**Linked:** commit hash + key files (`path:line`).
```

---

### YYYY-MM-DD — Session title

<!-- Replace this placeholder block with the actual entry for your first real session. -->

#### [EXAMPLE — delete before shipping]

**Decision:** Bootstrapped project with `project-scaffold` wizard; chose SQLite over Postgres for session storage.
**Why:** Single-node deployment, no concurrent-write requirement at launch. Postgres would add an ops dependency for no benefit at this scale.
**Alternatives:** (1) Postgres — rejected, single-node, disproportionate ops cost. (2) JSON file — rejected, no transactional guarantees if process crashes mid-write.
**Risks / weak spots:** SQLite single-writer. If write QPS exceeds ~200/s, queue depth grows. Monitor WAL file size. Rollback: swap adapter, restore backup.
**Linked:** commit `<hash>`, `src/db/session.ts:1-60`, `migrations/001.sql`.

<!-- END EXAMPLE -->
