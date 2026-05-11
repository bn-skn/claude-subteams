---
name: verification-gate
description: Use when about to claim work is complete, fixed, or passing. Requires running verification commands, backup before destructive changes, doc freshness checks, and stack-agnostic compilation checks. Evidence before assertions, always.
---

# Verification Gate

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you have not run the verification command in this message, you MUST NOT claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. BACKUP   → Create backup before any destructive change
2. IDENTIFY → What command proves this claim?
3. RUN      → Execute the FULL command (fresh, complete)
4. READ     → Full output, check exit code, count failures
5. VERIFY   → Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
6. DOCS     → Check documentation freshness
7. ONLY THEN → Make the claim

Skip any step = lying, not verifying
```

## Backup Before Destructive Changes

BEFORE any operation that modifies or deletes existing code:

1. Verify the current branch is committed or stashed
2. For file deletions: confirm the file is tracked in version control
3. For refactors: ensure tests pass BEFORE starting
4. For database migrations: back up the database first

**NEVER assume you can undo.** Git reflog is a last resort, not a strategy.

## Stack-Agnostic Compilation Check

ALWAYS run the appropriate compilation/type check before claiming code compiles:

| Stack | Command | What It Proves |
|-------|---------|----------------|
| TypeScript | `npx tsc --noEmit` | Type safety, no undefined references |
| Python | `mypy .` or `pyright .` | Type correctness |
| Go | `go build ./...` | Compilation, import resolution |
| Rust | `cargo check` | Compilation without full build |
| Java | `mvn compile` or `gradle compileJava` | Compilation |
| C/C++ | `make` or `cmake --build .` | Compilation, linking |
| Dart/Flutter | `dart analyze` | Static analysis |
| Swift | `swift build` | Compilation |

**Linter passing does NOT mean code compiles.** These are separate checks. ALWAYS run both.

## Documentation Freshness Check

BEFORE marking work complete, verify documentation is current:

1. If public API changed: update API docs
2. If new module added: update module index or README
3. If behavior changed: update relevant guides or comments
4. If config options changed: update config documentation

**Stale docs are bugs.** Treat them as blockers.

## Common Verification Failures

| Claim | Requires | NOT Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Types correct | Type checker: 0 errors | "TypeScript compiles" without running tsc |
| No regressions | Full test suite: all pass | Running only new tests |
| Requirements met | Line-by-line checklist | Tests passing |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| UI intact | Screenshot comparison: no visual regressions | tsc passes, unit tests pass |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit/push/PR without verification
- Trusting agent success reports
- Relying on partial verification
- Thinking "just this once"
- ANY wording implying success without having run verification

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence is not evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter is not compiler |
| "Agent said success" | Verify independently |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## Evidence Patterns

**Tests:**
```
CORRECT:  [Run test command] → [See: 34/34 pass] → "All tests pass"
WRONG:    "Should pass now" / "Looks correct"
```

**Build:**
```
CORRECT:  [Run build] → [See: exit 0] → "Build passes"
WRONG:    "Linter passed" (linter does not check compilation)
```

**Requirements:**
```
CORRECT:  Re-read plan → Create checklist → Verify each → Report gaps or completion
WRONG:    "Tests pass, phase complete"
```

## When to Apply

**ALWAYS before:**
- ANY variation of success/completion claims
- ANY expression of satisfaction
- ANY positive statement about work state
- Committing, PR creation, task completion
- Moving to next task
- Delegating to agents

## The Bottom Line

**No shortcuts for verification.**

Run the command. Read the output. Check the docs. THEN claim the result.

This is non-negotiable.
