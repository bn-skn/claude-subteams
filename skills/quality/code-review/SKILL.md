---
name: code-review
description: Structured code review checklist covering security, correctness, performance, maintainability, and SOLID principles. Defines WHAT to check and HOW to brief the code-reviewer agent.
requires: []
conflicts-with: []
type: rigid
---

# Code Review

## Overview

Code review is the last line of defense before code reaches production. This skill defines WHAT to check. The code-reviewer agent defines HOW to execute.

**Core principle:** Review for defects, not style preferences. Every finding MUST reference a concrete risk.

## When to Invoke

**ALWAYS for:**
- Any logic change in `src/`
- New module, class, or function
- Refactoring existing code
- Bug fixes
- Dependency additions or upgrades

**NEVER for:**
- Documentation or README changes only
- Config file formatting
- Cosmetic changes (whitespace, comment rewording)

## Review Checklist

### 1. Security

- [ ] No hardcoded secrets, API keys, or credentials
- [ ] User input is validated and sanitized before use
- [ ] SQL queries use parameterized statements
- [ ] File paths are validated against traversal attacks
- [ ] Authentication and authorization checks are present where required
- [ ] Sensitive data is not logged or exposed in error messages
- [ ] Dependencies have no known critical vulnerabilities

### 2. Correctness

- [ ] Logic matches the stated requirements
- [ ] Edge cases are handled (null, empty, boundary values)
- [ ] Error paths return meaningful results, not silent failures
- [ ] State mutations are intentional and documented
- [ ] Async operations handle errors and timeouts
- [ ] Return types match function signatures
- [ ] No dead code or unreachable branches

### 3. Performance

- [ ] No N+1 queries or unbounded loops
- [ ] Large datasets use pagination or streaming
- [ ] Expensive operations are cached where appropriate
- [ ] No unnecessary allocations in hot paths
- [ ] Database queries use appropriate indexes
- [ ] No blocking operations on the main thread

### 4. Maintainability

- [ ] Functions are under 50 lines (split if longer)
- [ ] Files are under 200 lines (extract if longer)
- [ ] Variable and function names describe their purpose
- [ ] No magic numbers — use named constants
- [ ] Complex logic has explanatory comments (why, not what)
- [ ] No duplicated code blocks (3+ occurrences = extract)

### 5. SOLID Principles

- [ ] **S** — Single Responsibility: each class/module has one reason to change
- [ ] **O** — Open/Closed: extensible without modifying existing code
- [ ] **L** — Liskov Substitution: subtypes are substitutable for base types
- [ ] **I** — Interface Segregation: no forced dependency on unused interfaces
- [ ] **D** — Dependency Inversion: depend on abstractions, not concretions

## Briefing the Code-Reviewer Agent

When delegating to the code-reviewer agent, provide:

1. **Changed files** — list every file with modifications
2. **Context** — what problem the change solves and why this approach was chosen
3. **Focus areas** — specific concerns (e.g., "concurrency safety in the queue module")
4. **Test status** — whether tests pass, what coverage looks like
5. **Known risks** — areas where you are uncertain or made trade-offs

```
Review these changes:
- Files: [list of changed files]
- Context: [problem statement and approach]
- Focus: [specific areas of concern]
- Tests: [pass/fail status, coverage]
- Risks: [known trade-offs or uncertainties]
```

## Handling Findings

### Critical Findings — Fix Before Commit

These MUST be resolved before the code is committed:

- Security vulnerabilities (injection, auth bypass, data exposure)
- Correctness bugs (wrong logic, missing error handling, data loss)
- Breaking changes without migration path
- Missing tests for critical paths

**Action:** Fix the code. Re-run tests. Re-review the fix.

### Suggestions — Discuss with User

These are improvements that do not block the commit:

- Performance optimizations for non-critical paths
- Naming improvements
- Refactoring opportunities
- Style preferences beyond the project linter

**Action:** Present to the user with rationale. Let them decide priority.

## Review Anti-Patterns

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| Rubber-stamping | Missing defects defeats the purpose |
| Style nitpicking | Wastes time on non-defects; use a linter |
| Reviewing only the diff | Context matters; check surrounding code |
| Skipping test review | Tests can have bugs too |
| "LGTM" without evidence | Same as not reviewing |
| Blocking on preferences | Preferences are not defects |

## The Bottom Line

Review for defects. Document findings with evidence. Critical issues block the commit. Everything else is a discussion.

NEVER approve code you have not read. NEVER skip a checklist item because it "probably" does not apply.
