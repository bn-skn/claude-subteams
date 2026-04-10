---
name: clean-architecture
description: Enforces layered architecture with strict dependency direction, file size limits, and naming conventions. Requires CONVENTIONS.md in project root.
sub-team: architecture
type: rigid
requires: [conventions-enforcer]
---

# Clean Architecture

## When to Apply

Use this skill when creating new modules, reviewing project structure, or running architecture guard checks. This skill is rigid -- all rules MUST be followed without exception.

## Prerequisites

1. CONVENTIONS.md MUST exist in the project root with numbered rules
2. If CONVENTIONS.md is missing, invoke the `conventions-enforcer` skill first to generate one

## Layer Structure

All code MUST follow this layer hierarchy (outermost to innermost):

```
presentation/ --> infrastructure/ --> application/ --> domain/
```

1. **domain/** -- Business entities, value objects, domain errors. NEVER imports from any other layer.
2. **application/** -- Use cases, ports (interfaces), DTOs. Imports only from domain/.
3. **infrastructure/** -- Repositories, external APIs, database clients. Imports from application/ and domain/.
4. **presentation/** -- Controllers, routes, CLI handlers, views. Imports from application/ and domain/.

## Dependency Rules

1. Dependencies MUST flow inward only (presentation -> infrastructure -> application -> domain)
2. domain/ MUST NOT import from application/, infrastructure/, or presentation/
3. application/ MUST NOT import from infrastructure/ or presentation/
4. Cross-layer communication MUST use interfaces (ports) defined in application/
5. NEVER create circular dependencies between layers
6. NEVER import concrete implementations across layer boundaries -- use dependency injection

## File Rules

1. Maximum 200 lines per file -- no exceptions
2. Maximum 30 lines per function or method
3. One exported thing per file (one class, one function, one constant object)
4. NEVER put multiple exports in a single file -- split them
5. Barrel files (index.ts) are allowed only at layer boundaries for re-exports

## Test Colocation

1. Tests MUST live next to the file they test: `thing.ts` + `thing.test.ts` in the same folder
2. NEVER put tests in a separate top-level `test/` or `__tests__/` directory
3. Integration tests go in the layer they primarily exercise
4. Test fixtures and helpers go in a `__fixtures__/` folder within the same layer

## Naming Conventions

1. Files: kebab-case (`user-repository.ts`, `create-order.ts`)
2. Classes: PascalCase (`UserRepository`, `CreateOrderUseCase`)
3. Functions: camelCase (`createUser`, `validateEmail`)
4. Constants: SCREAMING_SNAKE_CASE (`MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT`)
5. Interfaces/types: PascalCase, no `I` prefix (`UserRepository`, not `IUserRepository`)
6. NEVER use magic strings -- extract to named constants or enums

## Enforcement Checklist

1. [ ] CONVENTIONS.md exists and is up to date
2. [ ] All files are under 200 lines
3. [ ] All functions are under 30 lines
4. [ ] Each file has exactly one export
5. [ ] No domain/ imports from other layers (check with grep: `grep -r "from.*infrastructure\|from.*presentation\|from.*application" domain/`)
6. [ ] No application/ imports from infrastructure/ or presentation/
7. [ ] All file names are kebab-case
8. [ ] All tests are colocated with source files
9. [ ] No circular dependencies (run `npx dependency-cruiser --validate .depcruiserrc.json src/`)
10. [ ] No magic strings in business logic

## CI Integration

1. Configure dependency-cruiser with `.depcruiserrc.json` to validate import direction
2. Use `eslint-plugin-import/no-cycle` for circular dependency detection
3. The architecture-guard agent runs these checks at review time

## Red Flags

- File exceeding 200 lines -- split immediately
- Domain layer importing infrastructure code -- architectural violation
- Tests in a separate directory tree -- move them next to source
- Multiple exports from one file -- split into separate files
- Magic strings in conditionals or switch statements -- extract to constants
