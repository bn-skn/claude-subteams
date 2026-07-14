# <PROJECT_NAME>

<PROJECT_GOAL>

## Critical Constraints

- NEVER commit secrets or real credentials to the repository.
- NEVER bypass linting or type-checking steps before committing.
- ALWAYS run tests before marking any task done.
- See `docs/CONVENTIONS.md` for naming, file-size, and import rules.

## Stack

- **Language/runtime:** <STACK>
- **Key frameworks:** <FRAMEWORKS>
- **Persistence:** <DATABASE>
- **External APIs:** <EXTERNAL_APIS>

## Build & Test

```
<BUILD_COMMAND>      # build
<TEST_COMMAND>       # run all tests
<LINT_COMMAND>       # lint + type-check
```

## Architecture

- See `docs/ARCHITECTURE.md` for the full diagram and layer responsibilities.
- Dependency direction: presentation → application → domain. Infrastructure depends on application + domain. Never the reverse.
- Size: cohesion first — one semantic unit per file/function. Past the review threshold (default 300 lines file / 80 function, see CONVENTIONS.md) ask "still one responsibility?" — justify in one line or split by meaning.

## Methodology

For development tasks use the claude-subteams plugin (orchestrator + specialized agents).
Invoke skill `claude-subteams:using-subteams` before significant work.
For small fixes — act directly, invoke code-review after if logic changed.
See the plugin for the current agent roster.

## Doc Map

| What | Where |
|------|-------|
| Architecture | `docs/ARCHITECTURE.md` |
| Conventions | `docs/CONVENTIONS.md` |
| Backlog | `docs/BACKLOG.md` |
| Changelog | `docs/CHANGELOG.md` |
| System journal + decisions | `docs/SYSTEM.md` |
| Active plans | `docs/plans/active/` |
| Completed plans | `docs/plans/completed/` |
| Architecture decision records | `docs/adr/` |

## References

- `claude-subteams:decision-context` — write a decision block for every non-trivial change in `docs/SYSTEM.md`.
- `claude-subteams:conventions-enforcer` — check naming and structure before review.
- `claude-subteams:scaffolding` — add new components (services, modules, endpoints) to this project.
