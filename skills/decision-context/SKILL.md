---
name: decision-context
description: Mandatory "decision context" block for every non-trivial change documented in SYSTEM.md, CHANGELOG.md, session journals, or postmortems. Captures what was decided, why, what was rejected, what can break, and where to find related artifacts. Future-self insurance against cargo-cult and lost context.
---

# Decision Context

## Why This Exists

Six months from now, no one — not you, not a teammate, not a future LLM — will remember why a non-trivial change was made the way it was. Diffs show what changed. Commit subjects show the headline. Neither tells you what alternatives were rejected, what risks were accepted, or how to roll back if assumptions break.

A "decision context" block is a short, structured paragraph that captures the **why** alongside the **what**, written **at commit time, never later**. It lives wherever the project documents non-trivial work: a journal in `SYSTEM.md`, an entry in `CHANGELOG.md`, a session log, a postmortem.

This skill is the **everyday companion** to `adr-tracker`. ADRs are heavyweight, formal, one-file-per-decision, reserved for project-defining choices. The decision-context block is lightweight, inline, applies to every non-trivial commit. They complement each other — they do not overlap.

## When to Apply

Use this block whenever you add an entry to:

- `docs/SYSTEM.md` (or equivalent system journal / "session history")
- `CHANGELOG.md` for a release line that is more than a bullet list
- A session report, retro, or postmortem
- An entry in any append-only "decisions log" the project maintains

### Mandatory

Write the block when the change touches:

1. **Schema or data** — database migrations, breaking schema changes, new tables/collections
2. **Security** — auth, secrets handling, permissions model, prompt-injection defense
3. **Performance** — algorithm choice, caching strategy, bundle size, query optimization
4. **External integrations** — new API, new vendor, changed contract
5. **Pattern shift** — new architecture layer, new framework usage, change to a core abstraction
6. **Risky refactor** — large rename, dependency direction reversal, splitting a god-module
7. **New dependency** — any non-trivial library added or removed
8. **Algorithm choice** — when "obvious" wasn't picked, document why

### Skip (do not write the block)

- Cosmetic changes: whitespace, typo fixes, comment tweaks
- Patch-version bumps of dependencies with no behavior change
- Editing prose in `CLAUDE.md`, README, or other docs
- Adding a single fact to a curated knowledge file
- Pure formatting / linter auto-fixes

## Format

The block uses five fixed labels. Keep each line short. The whole block should fit on one screen.

```
**Decision:** one line — what was done.
**Why:** the problem this solves. If reproducible, how to reproduce.
**Alternatives:** what else was considered and why it was rejected. If there was no alternative, say "only option, because …".
**Risks / weak spots:** what can break, under what conditions. What to monitor. How to roll back.
**Linked:** commit hash + key files (`path:line`).
```

### Field discipline

- **Decision** — verbatim outcome, not the journey. "Switched session storage from JSON file to SQLite WAL." Not "After investigation, we decided to migrate to a more robust solution."
- **Why** — name the trigger. "Crashed on concurrent writes after 100+ active sessions." Reproducibility beats philosophy.
- **Alternatives** — at least one. If none considered, say so explicitly and explain why ("only viable option because [constraint]"). "No alternatives considered" is a smell — usually means thinking was skipped.
- **Risks / weak spots** — what would make a future engineer's day bad. "SQLite single-writer — if write QPS exceeds X, will queue. Monitor `WAL size` in dashboard. Rollback: revert commit + restore `sessions.json.bak`."
- **Linked** — commit hash and the two or three files that matter. Not the whole diff list.

## Examples

### Good (database migration)

```
**Decision:** Migrated `sessions` table from JSON file to SQLite with WAL mode.
**Why:** Concurrent writes from 4 background workers were corrupting the JSON
file under load. Reproducible by spawning 4 workers writing every 500 ms for
~30 s — JSON ends with a truncated trailing object.
**Alternatives:** (1) File-level lock with `proper-lockfile` — rejected because
write QPS was high enough that lock contention added 30–80 ms p99. (2) Postgres
— rejected because the app is single-node and adding a service for one table
was disproportionate. (3) Redis — rejected: no persistence guarantee.
**Risks / weak spots:** SQLite is single-writer. If session creation QPS exceeds
~200/s the queue depth grows; monitor `WAL size` and `pragma busy_timeout` hits.
Rollback: revert the commit and restore `store/sessions.json.bak`.
**Linked:** commit `8a336c3`, `src/db/sessions.ts:1-80`, `migrations/001.sql`.
```

### Good (algorithm choice)

```
**Decision:** Used incremental SHA-1 hashing (`crypto.createHash` stream) instead
of reading file then hashing.
**Why:** Files larger than 200 MB caused OOM on a 1 GB heap container.
Reproducible with the `huge-asset.bin` fixture in `test/fixtures/`.
**Alternatives:** (1) Bump container heap to 2 GB — rejected, masks the issue.
(2) MD5 — rejected, hash strength was a requirement.
**Risks / weak spots:** SHA-1 stream is ~15% slower on small files (<5 MB).
Acceptable because uploads are dominated by large files. Monitor `upload p99`.
**Linked:** commit `09acfd5`, `src/uploads/hash.ts:12-40`.
```

### Bad (do not do this)

```
**Decision:** Refactored upload code.
**Why:** It was messy.
**Alternatives:** N/A
**Risks / weak spots:** None that I can see.
**Linked:** see PR.
```

Why bad: every field is vacuous. "Messy" is not a problem statement. "N/A" hides whether thinking was done. "None that I can see" is the most dangerous sentence in engineering. "See PR" defeats the purpose — the whole point is to summarize so the reader does not need the PR.

## Workflow

1. Make the change. Run tests. Verify.
2. Before committing, draft the block in your head or in scratch.
3. Add the block as an entry in the project's decisions journal (`SYSTEM.md` or equivalent), under today's session heading.
4. Mirror the same content in the **commit body** — the block IS your commit body for non-trivial commits. (See `git-workflow` skill.)
5. Commit and push.

### When also creating an ADR

If the decision is project-defining (new dependency, framework choice, data-storage strategy, public API contract, deviation from established conventions), **also** create an ADR via `adr-tracker`. The block in the journal becomes a pointer; the ADR is the canonical record.

- Block in journal → quick context, scrollable in the session timeline
- ADR in `docs/adr/NNN-title.md` → discoverable as a standalone document, linked to from PRs and onboarding

## Cross-References

- `adr-tracker` — for project-defining decisions that warrant a standalone ADR file
- `git-workflow` — the commit body should mirror this block for non-trivial commits
- `claudemd-engineering` — for changes to `CLAUDE.md` itself (block usually not needed)
- `executing-plans` — block should be written at the end of each major plan step

## Red Flags

- A non-trivial commit landed without a block in the journal → write it retroactively, mark `**Linked:**` with the commit hash
- "Alternatives: N/A" appears more than once in a week → thinking is being skipped, not absent
- Block written days after the commit → context is already partially lost; the block is degraded but better than nothing
- Block exists only in commit body, not in the journal → future-self will never find it without `git log` archaeology
- Block exists only in the journal, not in commit body → reverse problem, harder to find when reading code
- Block is longer than ~12 lines → either too detailed (compress) or actually an ADR (escalate)

## Anti-Patterns

- **"We'll document it later."** No, you won't. Context decays in hours, not weeks.
- **Block as bureaucracy.** Six labels, six short lines, no ceremony. If it feels like paperwork, your block is too long.
- **Duplicating the diff.** The block summarizes intent, not implementation. The diff shows code.
- **Optimistic risk assessment.** "Low risk" with no monitoring or rollback plan is a tell that risks were not actually considered.
- **Vague linking.** "See PR" or "see the code" wastes the reader's time. Specific paths with line ranges.

## Bottom Line

A 5-line block, written once at commit time, saves hours of archaeology six months later. Skip it on cosmetics. Write it on anything that changes behavior, data, security, performance, or external contracts. Mirror it in the commit body. Escalate to an ADR when the decision is project-defining.

The block is the cheapest insurance you will ever buy against future confusion.
