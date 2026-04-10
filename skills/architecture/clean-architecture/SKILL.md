---
name: clean-architecture
description: Enforces layered architecture with strict dependency direction, file size limits, and naming conventions. Requires CONVENTIONS.md in project root.
sub-team: architecture
type: rigid
requires: [conventions-enforcer]
---

# Clean Architecture

## When to Apply

Use this skill when creating new modules, reviewing project structure, or running architecture guard checks. This skill is rigid — all rules MUST be followed without exception (see "When to Break the Rules" at the end for the one escape hatch).

## Prerequisites

1. CONVENTIONS.md MUST exist in the project root with numbered rules.
2. If CONVENTIONS.md is missing, invoke the `conventions-enforcer` skill first to generate one.

## Layer Diagram

```
┌─────────────────────────────────────────┐
│            Presentation                 │  ← HTTP controllers, CLI handlers,
│                                         │    Telegram bots, UI components
├─────────────────────────────────────────┤
│            Application                  │  ← Use cases, orchestration,
│                                         │    ports (interfaces), DTOs
├─────────────────────────────────────────┤
│              Domain                     │  ← Entities, value objects,
│                                         │    domain errors, business rules
└─────────────────────────────────────────┘
          ↑ Dependencies point INWARD

┌─────────────────────────────────────────┐
│           Infrastructure                │  ← DB clients, external APIs,
│                                         │    repositories, message queues
└─────────────────────────────────────────┘
  Implements interfaces defined in Application layer
```

**The golden rule:** dependencies ALWAYS point inward. Outer layers know about inner layers. Inner layers know NOTHING about outer layers. Domain is the center — it imports from NOBODY.

## Dependency Rules

1. **Domain imports NOTHING.** No application imports, no infrastructure imports, no presentation imports, no third-party libraries (except pure utility types). Domain is pure business logic.
2. **Application imports only from Domain.** Use cases orchestrate domain entities. They define ports (interfaces) that infrastructure must implement.
3. **Infrastructure imports from Application and Domain.** It implements the ports defined in Application. It adapts external services to domain types.
4. **Presentation imports from Application and Domain.** Controllers call use cases. They translate HTTP/CLI/UI input into application DTOs.
5. **Cross-layer communication MUST use interfaces (ports)** defined in Application. Never import concrete implementations across layer boundaries.
6. **NEVER create circular dependencies** between layers. If A imports B and B imports A — the architecture is broken.
7. **Use dependency injection** to provide concrete implementations to use cases at runtime.

### Dependency Direction Violations — How to Fix

| Violation | Fix |
|-----------|-----|
| Domain imports from Application | Extract the shared concept into Domain |
| Domain imports from Infrastructure | Define a port in Application, inject implementation |
| Application imports from Infrastructure | Define a port interface, depend on the abstraction |
| Application imports from Presentation | Move the shared type to Application or Domain |

## File Rules

These apply to CODE files only (not documentation, not config, not generated files).

### Size Limits

1. **Maximum 200 lines per file.** Files over 200 lines are doing too much.
2. **Maximum 30 lines per function or method.** Long functions hide complexity.
3. If a file or function exceeds the limit — split it. No exceptions (see "When to Break the Rules" below).

### Export Rules

1. **One exported thing per file** — one class, one function, one constant object.
2. NEVER put multiple exports in a single file. Split them.
3. **Barrel files** (index.ts) are allowed ONLY at layer boundaries for re-exports. They must contain nothing but re-export statements.

### Test Colocation

1. Tests MUST live next to the file they test: `thing.ts` + `thing.test.ts` in the same folder.
2. NEVER put tests in a separate top-level `test/` or `__tests__/` directory.
3. Integration tests go in the layer they primarily exercise.
4. Test fixtures and helpers go in a `__fixtures__/` folder within the same layer.

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Files | kebab-case | `user-repository.ts`, `create-order.ts` |
| Classes | PascalCase | `UserRepository`, `CreateOrderUseCase` |
| Functions | camelCase | `createUser`, `validateEmail` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT` |
| Interfaces/Types | PascalCase, no `I` prefix | `UserRepository`, NOT `IUserRepository` |
| Use cases | PascalCase + `UseCase` suffix | `CreateOrderUseCase` |
| Ports | PascalCase + descriptive name | `UserRepository`, `EmailSender` |
| Value objects | PascalCase | `EmailAddress`, `Money` |
| Domain errors | PascalCase + `Error` suffix | `UserNotFoundError` |

**NEVER use magic strings** — extract to named constants or enums. If a string appears in a conditional or switch statement, it must be a constant.

## God-File Detection

A "god-file" is a file that has grown to do too much. These are the most dangerous files in a codebase — they attract more code, create hidden coupling, and become impossible to test in isolation.

### Signs a File Is a God-File

| Signal | Threshold |
|--------|-----------|
| Line count | Over 200 lines |
| Import count | Imports 10+ modules |
| Responsibilities | Handles 3+ distinct concerns |
| Export count | Exports 3+ things |
| Change frequency | Touched by nearly every PR |
| Test difficulty | Tests require extensive mocking |
| Merge conflicts | Frequently causes merge conflicts |

### How to Split a God-File (Safely)

Splitting a god-file is surgery. Do it carefully.

1. **Read the entire file.** Identify distinct responsibilities. Write them down.
2. **Draw dependency lines.** Which functions call which? Which share state?
3. **Identify clusters.** Group functions by responsibility. Each cluster becomes a new file.
4. **Create new files one at a time.** Move ONE responsibility per commit.
5. **Update imports immediately** after each move. Run the compiler.
6. **Run tests after every move.** If tests break, fix before continuing.
7. **Update barrel files** (index.ts) if the old file was re-exported.
8. **Delete the old file** only after all responsibilities have moved out.

**NEVER do a "big bang" split** — moving everything at once. Move one cluster, verify, commit. Move next cluster, verify, commit. This makes rollback trivial.

## CONVENTIONS.md Requirement

Every project MUST have a `CONVENTIONS.md` in the project root. This file is the single source of truth for project-specific rules that complement clean architecture.

**CONVENTIONS.md must contain:**
- Numbered rules (for easy reference in code reviews)
- Layer structure description (matching this skill's layers)
- Technology-specific conventions (e.g., "Use Zod for validation, not class-validator")
- Import ordering rules
- Error handling conventions (exceptions vs. Result types)
- Naming overrides if the project deviates from defaults

If CONVENTIONS.md is missing, invoke `conventions-enforcer` to generate one before proceeding with any architectural work.

## Enforcement Mechanisms

### Automated Checks

1. **dependency-cruiser**: Configure `.depcruiserrc.json` to validate import direction. Run: `npx dependency-cruiser --validate .depcruiserrc.json src/`
2. **eslint-plugin-import**: Enable `import/no-cycle` for circular dependency detection.
3. **Architecture-guard agent**: A read-only subagent that runs these checks at review time. Grant tools: Read, Grep, Glob, Bash.

### Manual Checks (Enforcement Checklist)

1. [ ] CONVENTIONS.md exists and is up to date
2. [ ] All code files are under 200 lines
3. [ ] All functions are under 30 lines
4. [ ] Each file has exactly one export
5. [ ] Domain imports nothing from other layers
6. [ ] Application imports only from Domain
7. [ ] All file names are kebab-case
8. [ ] All tests are colocated with source files
9. [ ] No circular dependencies
10. [ ] No magic strings in business logic
11. [ ] No god-files (check import counts, line counts)

### Quick Validation Commands

```bash
# Check domain layer for forbidden imports
grep -r "from.*infrastructure\|from.*presentation\|from.*application" src/domain/

# Check application layer for forbidden imports
grep -r "from.*infrastructure\|from.*presentation" src/application/

# Find files over 200 lines
find src/ -name "*.ts" -exec awk 'END{if(NR>200) print FILENAME": "NR" lines"}' {} \;

# Find functions over 30 lines (approximate)
grep -n "function\|=>\|method" src/**/*.ts | head -50

# Find files with multiple exports
grep -rl "^export " src/ | xargs -I{} sh -c 'count=$(grep -c "^export " "{}"); [ "$count" -gt 1 ] && echo "{}: $count exports"'

# Run dependency-cruiser
npx dependency-cruiser --validate .depcruiserrc.json src/
```

## Anti-Patterns

### Feature Folders That Become God-Folders

```
BAD:  src/features/user/          ← 47 files, 3 layers mixed together
GOOD: src/domain/user/            ← entities, value objects
      src/application/user/       ← use cases, ports
      src/infrastructure/user/    ← repos, API clients
      src/presentation/user/      ← controllers, routes
```

Feature folders sound clean but collapse layer boundaries. When everything for "user" is in one folder, developers stop thinking about dependency direction. The folder becomes a mini-monolith.

### Shared Utils That Become Dumping Grounds

```
BAD:  src/shared/utils.ts         ← 800 lines, imports everything, used everywhere
GOOD: src/shared/string-utils.ts  ← 40 lines, pure functions, no imports
      src/shared/date-utils.ts    ← 35 lines, pure functions, no imports
      src/shared/result.ts        ← 50 lines, Result type definition
```

A `utils.ts` file is a god-file waiting to happen. Every "quick helper" gets dumped there. Within months it imports half the codebase and is imported by the other half — creating hidden circular dependencies across every layer.

### Leaking Infrastructure Into Domain

```
BAD:  // in domain/user.ts
      import { Column, Entity } from 'typeorm';

GOOD: // in domain/user.ts — pure, no ORM decorators
      export class User { ... }

      // in infrastructure/user-entity.ts — ORM mapping here
      import { Column, Entity } from 'typeorm';
```

ORM decorators, database types, and framework annotations do NOT belong in the Domain layer. Domain is pure business logic. Infrastructure adapts domain types to external systems.

### The "Just One More Import" Drift

Architecture violations don't happen in a single PR. They happen one import at a time:
1. "Just this once, I'll import the repo directly — it's faster."
2. "Well, that file already imports from infrastructure, so one more won't hurt."
3. Six months later: domain depends on infrastructure, and nobody remembers when it started.

**Every import is a dependency decision.** Review them with the same rigor as API changes.

## Red Flags Table

| Red Flag | What It Means | Action |
|----------|---------------|--------|
| File over 200 lines | God-file forming | Split immediately using the safe split procedure |
| Domain imports infrastructure | Architecture collapse | Extract port, inject implementation |
| Tests in separate `test/` tree | Testing friction, stale tests | Move next to source files |
| Multiple exports from one file | File doing too much | Split into one-export-per-file |
| Magic strings in conditionals | Fragile, untestable branching | Extract to named constants |
| `utils.ts` over 100 lines | Dumping ground forming | Split by responsibility |
| Import cycle detected | Layering broken | Restructure to break the cycle |
| 10+ imports in one file | Too many dependencies | File is doing too much — split it |
| `shared/` folder growing fast | Becoming a shadow layer | Review: does each file belong in a real layer? |
| Feature folder with 20+ files | Mini-monolith forming | Distribute files into proper layers |

## When to Break the Rules

Sometimes 250 lines is better than a forced abstraction that splits a cohesive concept into fragments nobody can understand. Sometimes a function needs 35 lines because splitting it creates two functions that only make sense together.

**The escape hatch:**
1. You genuinely believe breaking the rule produces BETTER code than following it.
2. You document WHY in an Architecture Decision Record (ADR) or a comment.
3. The violation is reviewed and approved by the architecture guard.
4. The exception is specific — "this file" or "this function" — not "we don't follow file limits."

**What is NOT a valid reason to break rules:**
- "It's faster to write it this way" — speed of writing is not a quality metric.
- "It's just a small project" — small projects become big projects.
- "We'll refactor later" — no you won't.
- "The deadline is tight" — technical debt compounds faster than financial debt.
