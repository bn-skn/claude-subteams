---
name: code-review
description: Structured code review checklist covering security, correctness, performance, maintainability, and SOLID principles. Defines WHAT to check and HOW to brief the code-reviewer agent.
---

# Code Review

## Overview

Code review is the last line of defense before code reaches production. This skill defines WHAT to check. The code-reviewer agent defines HOW to execute.

**Core principle:** Review for defects, not style preferences. Every finding MUST reference a concrete risk — "this input is not validated and could cause X" not "I prefer a different naming convention."

**Violating the letter of this rule is violating the spirit of this rule.**

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

| # | Check | What to Look For |
|---|-------|-----------------|
| 1.1 | **Hardcoded secrets** | API keys, passwords, tokens, connection strings in source. Check `.env` files are gitignored. |
| 1.2 | **Injection attacks** | SQL: are queries parameterized? NoSQL: are operators sanitized? Shell: is input escaped? |
| 1.3 | **Auth bypass** | Can any endpoint be reached without authentication? Are authorization checks on every mutation? |
| 1.4 | **Data exposure** | Are stack traces, internal IDs, or PII leaked in error responses? Are sensitive fields stripped from logs? |
| 1.5 | **Path traversal** | File operations validate paths? Symlink following disabled? User input never used in `fs.readFile` directly? |
| 1.6 | **Secrets in code** | `git log` search for accidentally committed secrets. Check for secrets in test fixtures. |
| 1.7 | **Dependency vulnerabilities** | Run `npm audit` / `pip audit`. No known critical CVEs in direct dependencies. |
| 1.8 | **CSRF / CORS** | Cross-origin policies configured? State-changing operations require CSRF tokens? |
| 1.9 | **Rate limiting** | Authentication endpoints rate-limited? Expensive operations throttled? |

### 2. Correctness

| # | Check | What to Look For |
|---|-------|-----------------|
| 2.1 | **Off-by-one errors** | Loop bounds, array indexing, pagination (page 0 vs page 1), substring ranges |
| 2.2 | **Null handling** | Every `.` chain could NPE. Optional chaining present where needed? Null checks before use? |
| 2.3 | **Error paths** | Every `try` has meaningful `catch`. Errors not swallowed silently. Async rejections handled. |
| 2.4 | **State management** | Mutations are intentional. No shared mutable state between requests. State transitions are valid. |
| 2.5 | **Async correctness** | No fire-and-forget promises. `await` present on every async call. Race conditions in shared state? |
| 2.6 | **Return types** | All branches return. Return types match signatures. No implicit `undefined` returns. |
| 2.7 | **Dead code** | Unreachable branches. Unused imports. Functions defined but never called. |
| 2.8 | **Edge cases** | Empty collections, single element, maximum size. First/last element behavior. |
| 2.9 | **Data consistency** | Transactions wrap related writes. Partial failure leaves consistent state. |

### 3. Performance

| # | Check | What to Look For |
|---|-------|-----------------|
| 3.1 | **N+1 queries** | Loop with a query inside. Should be a single query with IN clause or JOIN. |
| 3.2 | **Unnecessary re-renders** | React: missing `useMemo`/`useCallback` on expensive computations. Passing new object/array literals as props. |
| 3.3 | **Memory leaks** | Event listeners without cleanup. Growing caches without eviction. Closures holding references. |
| 3.4 | **Blocking I/O** | Synchronous file reads on main thread. `fs.readFileSync` in a request handler. |
| 3.5 | **Unbounded operations** | No pagination on list endpoints. Loading entire table into memory. Recursive functions without depth limit. |
| 3.6 | **Missing indexes** | Queries filtering on unindexed columns. Compound queries needing compound indexes. |
| 3.7 | **Unnecessary allocations** | Creating objects in hot loops. String concatenation in loops (use builder/join). |
| 3.8 | **Cache misuse** | Caching mutable data. No TTL on cache entries. Cache keys not accounting for all parameters. |

### 4. Maintainability

| # | Check | What to Look For |
|---|-------|-----------------|
| 4.1 | **Function length** | Over 50 lines? Split it. If you need to scroll to understand a function, it is too long. |
| 4.2 | **File length** | Over 300 lines? Extract modules. One file should have one clear responsibility. |
| 4.3 | **Naming clarity** | `data`, `info`, `result`, `temp` — these say nothing. Names must describe purpose. |
| 4.4 | **Magic numbers** | Raw numbers in logic (`if (status === 3)`). Use named constants. |
| 4.5 | **Dead code** | Commented-out blocks, unused variables, vestigial functions. Delete them; git has history. |
| 4.6 | **Duplication** | Same logic in 3+ places? Extract. Copy-paste code diverges and creates inconsistent bugs. |
| 4.7 | **Complexity** | Nested ternaries, 5+ level indentation, boolean expressions with 4+ terms. Simplify or extract. |
| 4.8 | **Coupling** | Module A importing internals of module B. Changes to B should not break A. |
| 4.9 | **Comments** | Comments that explain WHAT (redundant with code) instead of WHY (valuable context). |

### 5. SOLID Principles

| Principle | Check | Violation Signal |
|-----------|-------|-----------------|
| **S — Single Responsibility** | Does this class/module have one reason to change? | File handles HTTP, validation, database, AND email. |
| **O — Open/Closed** | Can behavior be extended without modifying existing code? | Adding a new payment type requires editing a switch statement in 5 files. |
| **L — Liskov Substitution** | Can subtypes replace base types without breaking callers? | Subclass throws on a method the base class supports. |
| **I — Interface Segregation** | Are clients forced to depend on methods they do not use? | A plugin interface has 20 methods but most plugins use 3. |
| **D — Dependency Inversion** | Do modules depend on abstractions or concretions? | Business logic imports a specific database driver directly. |

## How to Brief the Code-Reviewer Agent

When delegating to the code-reviewer agent, provide this exact format:

```
REVIEW REQUEST
==============

Changed files:
- src/auth/login.ts (modified — added rate limiting)
- src/auth/session.ts (new file — session management)
- src/middleware/rateLimit.ts (new file — rate limiter)

Context:
Adding rate limiting to the login endpoint to prevent brute-force attacks.
Approach: token bucket algorithm with Redis backing store.

Focus areas:
1. Race condition in token bucket increment (concurrent requests)
2. Session token generation — is it cryptographically secure?
3. Error handling when Redis is unavailable

Test status:
- Unit tests: 14/14 passing
- Integration tests: 8/8 passing
- Coverage: 87% on changed files

Known risks:
- Redis connection pooling may need tuning under load
- Session expiry relies on Redis TTL, no application-level cleanup
```

**Required fields — never omit:**
1. **Changed files** — every file with what changed and why
2. **Context** — the problem being solved and the approach chosen
3. **Focus areas** — specific concerns ranked by risk (most dangerous first)
4. **Test status** — pass/fail counts, coverage on changed files
5. **Known risks** — trade-offs you made, areas where you are uncertain

**Auto-scan commands to include:**
```bash
# TypeScript
npx tsc --noEmit 2>&1 | tail -20

# Python
python -m py_compile src/module.py && echo "OK"
ruff check src/ --select=E,W,F

# Bash
shellcheck scripts/*.sh
```

Include the output of these scans in the review request so the reviewer has static analysis results.

## Handling Findings

### Critical — Fix Before Commit

These BLOCK the commit. No exceptions, no deferral.

- Security vulnerabilities (injection, auth bypass, data exposure, secrets in code)
- Correctness bugs (wrong logic, data loss, missing error handling on critical paths)
- Breaking changes to public APIs without migration path
- Missing tests for critical business logic

**Action:** Fix the code. Re-run tests. Re-review the fix. Do not commit until resolved.

### Important — Fix Now

These should be fixed in the current session but do not block an intermediate commit:

- Performance issues on hot paths (N+1 queries, missing indexes)
- Missing error handling on non-critical paths
- SOLID violations that will make the next change painful
- Test gaps on edge cases

**Action:** Fix them. Add a test for each fix. Re-run the suite.

### Suggestions — Discuss with User

These are improvements that do not block the commit:

- Performance optimizations for non-critical paths
- Naming improvements
- Refactoring opportunities for better maintainability
- Style preferences beyond the project linter

**Action:** Present to the user with rationale and concrete impact. Let them decide priority.

## Review Anti-Patterns

| # | Anti-Pattern | Why It Fails | What to Do Instead |
|---|-------------|-------------|-------------------|
| 1 | **Rubber-stamping** | Missing defects defeats the entire purpose of review | Walk through every checklist item. If you cannot find issues, you are not looking hard enough. |
| 2 | **Style nitpicking** | Wastes time on non-defects; creates friction without value | Use a linter. Review findings must reference a concrete risk, not a preference. |
| 3 | **Reviewing only the diff** | Context matters; a change correct in isolation can break the surrounding code | Read the full file. Check callers. Check what imports this module. |
| 4 | **Reviewing too much at once** | Cognitive overload causes reviewers to skim. Defects hide in large diffs. | Break large changes into reviewable chunks. 400+ line diffs get a second pass. |
| 5 | **Skipping test review** | Tests can have bugs. Incorrect tests give false confidence. | Review tests with the same rigor as production code. |
| 6 | **"LGTM" without evidence** | Same as not reviewing. No checklist walked, no findings documented. | Every review must reference specific checklist items checked. |
| 7 | **Blocking on preferences** | Preferences are not defects. Disagreement on style should not block a commit. | If the linter passes and the logic is correct, approve. |
| 8 | **Ignoring test gaps** | "Tests pass" is not "tests are sufficient." Missing tests are a finding. | Check coverage on changed lines. Missing edge case tests are Important findings. |

## Red Flags — Rationalizations During Review

| # | Rationalization | Reality |
|---|----------------|---------|
| 1 | "The author is senior, their code is fine" | Seniority does not prevent bugs. Review the code, not the author. |
| 2 | "I don't understand this part, but it probably works" | If you cannot understand it, you cannot review it. Ask for explanation. |
| 3 | "It has tests, so it's correct" | Tests can be wrong, incomplete, or test the wrong thing. Review the tests. |
| 4 | "This is a small change, no need for full review" | Small changes cause large incidents. Check the full checklist. |
| 5 | "We can fix it in the next PR" | "Next PR" means "never." Fix it now. |
| 6 | "The deadline is tight, just approve it" | Shipping bugs is slower than fixing them before commit. |
| 7 | "It works in my testing" | Your test environment is not production. Check the edge cases in the checklist. |
| 8 | "The CI passed" | CI checks syntax and runs existing tests. It does not check for missing tests, logic errors, or security issues. |
| 9 | "I'll review it more carefully later" | You will not. Review thoroughly now. |
| 10 | "It's just refactoring, behavior didn't change" | Refactoring is where subtle bugs hide. Verify behavior preservation with tests. |

## After Review: Next Steps

### Full Pipeline (Recommended)

After code review passes, proceed to **devils-advocate** — a challenge pass that questions assumptions, edge cases, scale, and necessity. This catches design-level issues that implementation-focused review misses.

Pipeline: `code-review` -> `devils-advocate` -> `adversarial-testing`

### Lightweight Pipeline

When time is constrained or changes are low-risk, skip devils-advocate and go directly to testing:

Pipeline: `code-review` -> `adversarial-testing`

Choose the lightweight pipeline ONLY when:
- Change is under 50 lines
- Change is in non-critical path (not auth, not payments, not data integrity)
- Change has comprehensive existing test coverage
- Reviewer found zero Critical or Important findings

If in doubt, use the full pipeline.

## The Bottom Line

Review for defects. Document findings with evidence. Critical issues block the commit. Everything else is a discussion.

NEVER approve code you have not read. NEVER skip a checklist item because it "probably" does not apply. NEVER rubber-stamp because the author is experienced or the change looks simple.

A review that finds nothing is either thorough (rare) or negligent (common). Challenge yourself: if the code ships and breaks, will you be confident your review was rigorous?
