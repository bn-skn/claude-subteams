---
name: adversarial-testing
description: Try to BREAK the code, not confirm it works. Write tests that find bugs through edge cases, invalid data, race conditions, and boundary violations.
requires: []
conflicts-with: [test-driven-development]
type: rigid
---

# Adversarial Testing

## Overview

Testing is not about proving code works. Testing is about proving code BREAKS.

**Core principle:** Every test MUST attempt to destroy a specific assumption. If your test only confirms the happy path, it is worthless.

**Violating the letter of this rule is violating the spirit of this rule.**

## When to Invoke

**ALWAYS for:**
- Any logic change in `src/`
- New module or function
- Refactoring existing code
- Bug fixes (prove the fix AND find siblings)

**NEVER for:**
- Documentation or README changes
- Config file updates (unless config drives logic)
- Cosmetic changes (whitespace, comments, renaming)

## The 6-Step Process

```
1. RECEIVE  → Identify changed files, functions, and assumptions
2. UNIT     → Write unit tests targeting each function in isolation
3. INTEGRATE → Write integration tests crossing module boundaries
4. ATTACK   → Adversarial checks: edge cases, invalid data, race conditions
5. RUN      → Execute ALL tests, read ALL output, check exit codes
6. VERDICT  → Pass (all green) or Blocker (failures listed with evidence)
```

### Step 1: Receive Changes

1. List every changed file and function
2. Identify each assumption the code makes (input types, ranges, ordering, availability)
3. Map dependencies between changed modules

### Step 2: Unit Tests

1. Write at least one test per public function
2. Test the contract, not the implementation
3. NEVER mock the unit under test — only its dependencies
4. Each test MUST have a clear name describing the scenario

### Step 3: Integration Tests

1. Test module boundaries — where data crosses from one module to another
2. Test real dependencies when possible (use test databases, not mocks)
3. Verify end-to-end data flow through the changed path
4. Test that error propagation works across module boundaries

### Step 4: Adversarial Checks

This is the core of adversarial testing. For every function, systematically attack:

| Attack Vector | Examples |
|---------------|----------|
| **Null/undefined** | null, undefined, empty string, empty array, empty object |
| **Boundary values** | 0, -1, MAX_INT, MAX_INT+1, empty, one element, max length |
| **Type coercion** | "123" vs 123, true vs 1, [] vs false |
| **Concurrency** | Parallel calls, out-of-order responses, duplicate requests |
| **Resource exhaustion** | Very large inputs, deep nesting, circular references |
| **Malicious input** | SQL injection, XSS payloads, path traversal, prototype pollution |
| **Timing** | Timeouts, slow responses, zero-latency assumptions |
| **State corruption** | Partial failures, interrupted writes, stale cache |

### Step 5: Run All Tests

1. Execute the FULL test suite — not just new tests
2. Read ALL output — do not skim
3. Check exit code — zero means pass, anything else means fail
4. Count failures and errors separately

### Step 6: Verdict

**PASS:** All tests green, exit code 0, no warnings that indicate real problems.

**BLOCKER:** Any failure. List each failure with:
- Test name
- Expected vs actual
- Root cause assessment
- Severity (critical / high / medium)

NEVER downgrade a blocker. NEVER say "probably fine." Fix or escalate.

## Red Flags Table

| Red Flag | What It Means |
|----------|---------------|
| All tests pass on first run | You tested the happy path, not the edges |
| No tests for error paths | You assumed errors do not happen |
| Every test uses mocks | You tested your mocks, not your code |
| Tests mirror implementation | Refactoring will break tests without finding bugs |
| No boundary value tests | Off-by-one errors will ship |
| "Too simple to test" | Simple code breaks. Test it. |
| Test names say "works" or "correct" | Vague names hide vague tests |

## Adversarial Mindset Checklist

Before marking tests complete, confirm:

- [ ] At least one test per function targets an error path
- [ ] Boundary values tested for every numeric parameter
- [ ] Null/empty tested for every reference parameter
- [ ] At least one test attempts to break type assumptions
- [ ] Integration tests cross at least one module boundary
- [ ] No test exists solely to confirm the happy path
- [ ] Every test name describes the specific scenario it attacks
- [ ] All tests run and all output has been read

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to break" | Simple code has simple bugs. 30-second test catches them. |
| "Edge cases are unlikely" | Unlikely in dev. Guaranteed in production. |
| "Mocks are faster" | Fast wrong tests are worse than slow correct tests. |
| "Integration tests are slow" | Slow tests that find bugs beat fast tests that miss them. |
| "I tested manually" | Manual tests vanish. Automated tests persist. |
| "The type system prevents this" | Runtime does not care about your types. |

## The Bottom Line

If you only wrote tests that pass, you did not test. You confirmed your assumptions.

**Write tests that SHOULD fail. Then make them pass. Then find the next way to break it.**
