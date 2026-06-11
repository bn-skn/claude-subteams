# Conventions

> STATUS: TEMPLATE — not yet populated

## 1. File Structure

```
src/
  domain/          # Entities, value objects, domain services — no external deps
  application/     # Use cases, orchestration — depends on domain only
  infrastructure/  # DB, HTTP, external APIs — depends on application + domain
  presentation/    # UI, CLI, controllers — depends on application only
```

## 2. File Size Limits

1. Max **200 lines** per file. Split if exceeded.
2. Max **30 lines** per function. Extract helpers if exceeded.
3. One exported thing per file (class, function, constant, type).

## 3. Dependency Direction

Always inward: `presentation → application → domain`. Never the reverse.
`infrastructure` may depend on `application` and `domain`.
No circular dependencies.

## 4. Test Colocation

Tests live next to the file they test:

```
user-service.ts
user-service.test.ts
```

## 5. Naming

| Thing | Convention | Example |
|---|---|---|
| Files | kebab-case | `user-service.ts` |
| Classes | PascalCase | `UserService` |
| Functions / variables | camelCase | `getUserById` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRIES` |
| Types / Interfaces | PascalCase | `UserDto` |

## 6. No Magic Strings

All string literals that carry meaning must be named constants or enum values.

```ts
// Bad
if (status === 'active') { ... }

// Good
const STATUS_ACTIVE = 'active';
if (status === STATUS_ACTIVE) { ... }
```

## 7. Imports

1. Absolute imports over relative when more than 2 levels deep.
2. No barrel files (`index.ts` re-exporting everything) — import directly.
3. Third-party imports first, then internal imports, separated by a blank line.

## 8. Error Handling

1. Never swallow errors silently (`catch (e) {}`).
2. Wrap external calls in try/catch with typed error handling.
3. Use result types or typed errors — no stringly typed error messages in logic.
