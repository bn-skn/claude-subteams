---
name: doc-quality-gate
description: "Classifies change severity (cosmetic/feature/architectural/breaking) and defines per-class documentation requirements."
---

# Doc Quality Gate

## 1. When to Use This Skill

1. When ending a session that involved code changes.
2. When the `session-end-reminder` hook fires with breaking/architectural signals.
3. When deciding which documentation artifacts a change requires.
4. When asked "what docs does this change need?" or "is this a breaking change?".

Note: the hook detects file signals and reminds — it cannot verify documentation content or quality. Real verification of a breaking change requires the doc-agent breaking-change audit plus your judgment.

## 2. Change Classes

Classify the change into exactly one class. For block format, field discipline, and mandatory/skip triggers for the decision-context block, see `claude-subteams:decision-context` — not restated here.

### Class 1 — Cosmetic

Examples: whitespace, typos, comment tweaks, lint autofix, patch-version bumps with no behavior change. A plugin.json change that only bumps a patch version with no behavior change is also cosmetic.

**Doc requirements:** none. State in your stop message why docs are not needed.

### Class 2 — Feature Add

Examples: new function/endpoint/route/module added, new config option, new dependency added, new capability — no existing contract broken or removed.

**Doc requirements:**
1. CHANGELOG.md entry for any user-visible or release-relevant feature; AND a BACKLOG.md status update if the work was tracked there (mark the item done). When both apply, update both — updating only one is the common miss. (Internal-only plumbing that is not release-relevant may skip CHANGELOG; say so in your stop message.)
2. Extend the descriptive section of SYSTEM.md (or equivalent) if the architecture changed.
3. Decision-context block only if the implementation involved a non-obvious choice (see decision-context skill).
4. Doc-map entry — see section 2.5 (any new tracked doc requires it, independent of class).

### Class 3 — Architectural

Examples: new layer or module, pattern shift, risky refactor, new non-trivial dependency, schema change without data-migration impact, plugin.json contract change that adds capability without removing any.

**Doc requirements:**
1. Mandatory decision-context block (Decision / Why / Alternatives / Risks / Linked).
2. Overwrite (do not append) the descriptive section of SYSTEM.md.
3. CHANGELOG.md entry.
4. Consider dispatching doc-agent in audit mode to catch stale references.

### Class 4 — Breaking

Examples: removed functionality, changed or removed route/endpoint/proto field, schema migration with data impact, renamed public symbol with no backward-compat shim, changed integration contract, plugin.json change that removes or renames a previously stable field.

**Doc requirements:**
1. Rewrite the descriptive section of SYSTEM.md — start fresh, do not patch.
2. Mandatory decision-context block with non-empty Alternatives and Risks fields.
3. CHANGELOG.md entry (major or minor version line).
4. Migration guide if any existing integration or consumer breaks.
5. API/contract docs updated (OpenAPI spec, .proto file headers, plugin.json).
6. Dispatch doc-agent in breaking-change audit mode (section 5).

## 2.5 Cross-cutting: doc-map freshness

When a change **adds a new tracked doc** — a new `docs/specs/*` file or an ADR (`docs/adr/`) — it MUST also add a corresponding entry to the project's **doc map** (`docs/INDEX.md` or equivalent) in the same change, *regardless of the code change's class*. This applies even when the code change itself is Cosmetic (Class 1): "Doc requirements: none" governs the per-class requirements for the *code*, while an added doc independently owes a doc-map entry. (Plans under `docs/plans/` are tracked by the living-plan gate, not this rule.)

The doc map is the discovery surface; a new doc with a stale index silently reads as "the doc set is complete" when it is not, and breaks any conventions check that trusts the index. **If the project has no doc map, this requirement does not apply — do not create one solely to satisfy it.**

This is the gap the freshness gate previously missed: a commit of "code + a new spec" satisfied the per-class rules (a `.md` was touched) while the index quietly fell behind. The `session-end-reminder` hook now flags a changeset that introduces a new doc under `docs/specs/` or `docs/adr/` while the project's doc map — auto-detected from common names, or set via `CLAUDE_SUBTEAMS_DOC_MAP` — is left untouched. The hook stays silent when no doc map exists.

## 3. Signal → Class Mapping

The `session-end-reminder` hook detects only two reliable file signals (deletions and schema/migration files). Everything else is classified by the model using judgment.

### Hook-flagged signals (hook escalates the block message)

| Hook signal | Minimum class |
|-------------|---------------|
| File deleted (git status `D`) | Breaking |
| `migrations/`, `.sql`, `.prisma`, `schema.` | Architectural or Breaking — use data-impact to decide |

### Model-judgment signals (hook does NOT flag these; you classify)

| File pattern | Default class | Upgrade condition |
|--------------|--------------|-------------------|
| Dependency manifest (`package.json`, `go.mod`, etc.) | Architectural | Breaking if existing behavior removed |
| New route/endpoint/proto field | Feature | — |
| Changed or removed route/endpoint/proto field | Breaking | — |
| `plugin.json` — patch-only version bump | Cosmetic | — |
| `plugin.json` — adds capability | Architectural | — |
| `plugin.json` — removes/renames stable field | Breaking | — |

When the hook fires: use this skill to pin the class, then apply the per-class requirements from section 2.

## 4. When to Dispatch doc-agent

1. **Breaking (class 4):** ALWAYS dispatch doc-agent in breaking-change audit mode.
2. **Architectural (class 3):** dispatch if any public API, integration doc, or SYSTEM.md descriptive section was touched.
3. **Feature add (class 2):** optional; dispatch if the feature added a new public surface.
4. **Cosmetic (class 1):** NEVER dispatch doc-agent.

Invocation: call the `doc-agent` subagent and specify mode `breaking-change audit` for class 4, `audit` for class 3.

## 5. Quick Reference

| Class | CHANGELOG | Decision-context block | Descriptive section | Migration guide | doc-agent |
|-------|-----------|----------------------|---------------------|-----------------|-----------|
| Cosmetic | No | No | No | No | No |
| Feature add | Yes | If non-obvious choice | Extend if changed | No | Optional |
| Architectural | Yes | Mandatory | Overwrite | No | Recommended |
| Breaking | Yes | Mandatory (full fields) | Rewrite | If integrations break | Always |

Independent of class: any new tracked doc (spec / ADR) requires a doc-map (`docs/INDEX.md` or equivalent) entry when the project has one — see section 2.5.

## 6. Red Flags

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| Calling a deletion "cosmetic" | Removed functionality breaks callers — class 4 minimum | Apply breaking-change checklist; write migration guide |
| Appending to descriptive section instead of overwriting | Stale description persists alongside new facts, causing contradictions | Overwrite the entire descriptive section |
| Decision-context block with empty Alternatives field | Signals thinking was skipped, not that alternatives were absent | State "only option because …" with a concrete constraint |
| No CHANGELOG entry for a new dependency | Dependency changes affect reproducibility and security posture | Add CHANGELOG entry; classify as Architectural minimum |
| Skipping doc-agent after a breaking change | Stale migration guides and API docs will mislead future integrators | Dispatch doc-agent in breaking-change audit mode before stopping |
| Classifying a changed/removed route or proto field as "feature add" | Changed contracts break existing callers silently | Reclassify as Breaking; check all callers; write migration note |
| Adding a new spec/ADR without updating the doc map (`docs/INDEX.md` or equivalent) | The index silently lags; future sessions and any conventions check treat the doc set as complete when it is not | Add the doc-map entry in the same change (section 2.5); heed the hook's new-doc/stale-map reminder |
| Updating only BACKLOG or only CHANGELOG when both apply | The other tracker drifts; release notes or task status goes stale | When both a CHANGELOG entry and a BACKLOG item apply, update both; mark the BACKLOG item done if it was tracked |

## 7. Critical Rules

1. NEVER classify a file deletion as cosmetic or feature add.
2. ALWAYS dispatch doc-agent for breaking changes before stopping the session.
3. MUST apply at least the minimum class from the signal tables; NEVER downgrade based on gut feeling.
4. NEVER ship a breaking change without a CHANGELOG entry.
5. For decision-context block rules (overwrite vs append, Alternatives field discipline) — follow `claude-subteams:decision-context`, not this skill.
6. MUST update the doc map (`docs/INDEX.md` or equivalent), when the project has one, whenever a change adds a new tracked doc (spec or ADR). A new doc with a stale index is an incomplete change (section 2.5).

## 8. Cross-References

- `decision-context` — block format, mandatory/skip triggers, field discipline.
- `doc-agent` — audit, update, and breaking-change audit modes.
- `session-end-reminder` hook — file-signal detection and escalation behavior.
- `adr-tracker` — for project-defining decisions that warrant a standalone ADR.
