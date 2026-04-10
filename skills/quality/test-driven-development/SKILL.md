---
name: test-driven-development
description: Red-Green-Refactor cycle. Write the test first, watch it fail, write minimal code to pass. Optional alternative to adversarial-testing.
requires: []
conflicts-with: [adversarial-testing]
type: rigid
---

# Test-Driven Development (TDD)

> **This is an OPTIONAL alternative to adversarial-testing.** Use TDD when:
> - Writing a library with a clear public API
> - The user explicitly requests TDD
> - Complex algorithm where test cases help clarify requirements
>
> For most feature work and bug fixes, adversarial-testing is the default.

## Overview

Write the test first. Watch it fail. Write minimal code to pass.

**Core principle:** If you did not watch the test fail, you do not know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**

## When to Use

**Always (when TDD is selected):**
- New features
- Bug fixes
- Refactoring
- Behavior changes

**Exceptions (ask the user):**
- Throwaway prototypes
- Generated code
- Configuration files

Thinking "skip TDD just this once"? Stop. That is rationalization.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over.

**No exceptions:**
- Do not keep it as "reference"
- Do not "adapt" it while writing tests
- Do not look at it
- Delete means delete

Implement fresh from tests. Period.

## Red-Green-Refactor

### RED - Write Failing Test

1. Write ONE minimal test showing what should happen
2. Use a clear name describing the behavior
3. Test real code, not mocks (unless unavoidable)
4. One behavior per test — "and" in the name means split it

### Verify RED - Watch It Fail

**MANDATORY. NEVER skip.**

```bash
[run test command for your stack]
```

Confirm:
- Test fails (not errors)
- Failure message is expected
- Fails because feature is missing (not typos)

**Test passes?** You are testing existing behavior. Fix the test.

**Test errors?** Fix the error, re-run until it fails correctly.

### GREEN - Minimal Code

1. Write the SIMPLEST code that makes the test pass
2. Do not add features beyond the test
3. Do not refactor other code
4. Do not "improve" beyond what the test requires

### Verify GREEN - Watch It Pass

**MANDATORY.**

```bash
[run test command for your stack]
```

Confirm:
- Test passes
- Other tests still pass
- Output is clean (no errors, warnings)

**Test fails?** Fix the code, not the test.

**Other tests fail?** Fix them now.

### REFACTOR - Clean Up

After green only:
- Remove duplication
- Improve names
- Extract helpers

Keep tests green. Do not add behavior.

### Repeat

Next failing test for the next behavior.

## Good Tests

| Quality | Good | Bad |
|---------|------|-----|
| **Minimal** | One thing. "and" in name? Split it. | `test('validates email and domain and whitespace')` |
| **Clear** | Name describes behavior | `test('test1')` |
| **Shows intent** | Demonstrates desired API | Obscures what code should do |
| **Real code** | Tests actual implementation | Tests mock behavior |

## Why Test-First Matters

- **Tests-after** answer "What does this do?"
- **Tests-first** answer "What SHOULD this do?"

Tests written after code pass immediately. Passing immediately proves nothing:
- Might test the wrong thing
- Might test implementation, not behavior
- Might miss edge cases you forgot
- You never saw it catch the bug

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. Keeping unverified code is technical debt. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "Test hard = skip test" | Hard to test = hard to use. Listen to the test. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "Keep as reference" | You will adapt it. That is testing after. Delete means delete. |

## Red Flags - STOP and Start Over

- Code before test
- Test after implementation
- Test passes immediately
- Cannot explain why test failed
- Tests added "later"
- Rationalizing "just this once"
- "Keep as reference" or "adapt existing code"
- "Already spent X hours, deleting is wasteful"

**All of these mean: Delete the code. Start over with TDD.**

## Verification Checklist

Before marking work complete:

- [ ] Every new function has a test
- [ ] Watched each test fail before implementing
- [ ] Each test failed for the expected reason
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass
- [ ] Output is clean (no errors, warnings)
- [ ] Tests use real code (mocks only if unavoidable)
- [ ] Edge cases and error paths covered

Cannot check all boxes? You skipped TDD. Start over.

## Debugging Integration

Bug found? Write a failing test reproducing it. Follow the TDD cycle. The test proves the fix and prevents regression.

NEVER fix bugs without a test.

## The Bottom Line

```
Production code exists → a test exists that failed first
Otherwise → not TDD
```

No exceptions without the user's explicit permission.
