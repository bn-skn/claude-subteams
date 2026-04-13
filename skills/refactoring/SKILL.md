---
name: refactoring
description: When and how to refactor safely. Identifies god-files, circular dependencies, and DRY violations. Small steps with tests at every stage.
---

# Refactoring

## Overview

Refactoring is restructuring existing code without changing its external behavior. Every refactoring step MUST preserve all existing tests.

**Core principle:** Small steps, verified continuously. If tests break, you went too far.

## When to Refactor

### Trigger Thresholds

| Signal | Threshold | Action |
|--------|-----------|--------|
| **God-file** | File exceeds 200 lines | Extract classes or modules |
| **God-function** | Function exceeds 50 lines | Extract helper functions |
| **Duplication** | 3+ identical or near-identical blocks | Extract shared function (DRY threshold) |
| **Circular deps** | Module A imports B, B imports A | Introduce interface or mediator |
| **Shotgun surgery** | Single change touches 5+ files | Consolidate related logic |
| **Feature envy** | Function uses another class more than its own | Move function to the other class |
| **Deep nesting** | 4+ levels of indentation | Extract early returns or helper functions |

### When NOT to Refactor

1. **NEVER refactor unrelated code while fixing a bug** — fix the bug, commit, then refactor separately
2. **NEVER refactor without passing tests first** — if tests are broken, fix them before restructuring
3. **NEVER refactor and add features in the same commit** — one concern per commit
4. **NEVER refactor code you do not understand** — read it, test it, then refactor it
5. **NEVER refactor to a pattern just because it exists** — refactor toward a specific, measurable improvement

## The Safe Refactoring Process

```
1. VERIFY  → All existing tests pass (run full suite)
2. PLAN    → Identify what changes and what stays the same
3. STEP    → Make ONE small structural change
4. TEST    → Run tests — they MUST still pass
5. COMMIT  → Commit the passing state
6. REPEAT  → Next small step, or stop if done
```

**If tests fail at step 4:** Revert the step. Do not debug forward. Make a smaller step.

## Refactoring Patterns

### Extract Method

**When:** A block of code inside a function does one identifiable thing.

1. Identify the block and its inputs/outputs
2. Create a new function with a descriptive name
3. Move the block into the new function
4. Replace the original block with a call to the new function
5. Run tests

### Extract Class / Module

**When:** A file or class has multiple responsibilities (god-file).

1. Identify the distinct responsibilities
2. Create a new file/class for each extracted responsibility
3. Move related functions and data to the new class
4. Update imports in all consumers
5. Run tests after each move

### Dependency Inversion

**When:** High-level modules depend on low-level details.

1. Define an interface for the dependency
2. Make the high-level module depend on the interface
3. Make the low-level module implement the interface
4. Inject the dependency at construction time
5. Run tests

### Replace Conditional with Polymorphism

**When:** A switch/if-else chain selects behavior based on type.

1. Create a base class or interface for the behavior
2. Create a subclass for each branch
3. Move branch logic into the corresponding subclass
4. Replace the conditional with a method call on the polymorphic object
5. Run tests

### Repository Pattern

**When:** Data access logic is scattered across business logic.

1. Create a repository interface defining data operations
2. Implement the repository with actual data access
3. Replace direct data access calls with repository calls
4. Inject the repository where needed
5. Run tests

## Measuring Improvement

EVERY refactoring MUST produce at least one measurable improvement:

- [ ] Reduced file line count (toward the 200-line target)
- [ ] Reduced function line count (toward the 50-line target)
- [ ] Eliminated code duplication (fewer repeated blocks)
- [ ] Removed circular dependency
- [ ] Reduced coupling (fewer imports per module)
- [ ] Improved naming (intent is clearer)

If you cannot identify the improvement, do not refactor.

## Anti-Patterns

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| Big-bang refactor | Too many changes at once; impossible to debug failures |
| Refactor during bug fix | Mixes concerns; hides whether the bug fix or refactor caused issues |
| Refactor without tests | No safety net; you do not know if behavior changed |
| Refactor to a pattern for its own sake | Adds complexity without solving a problem |
| "While I'm here" changes | Scope creep; increases risk for no planned benefit |
| Refactoring code you just wrote | Design it correctly the first time; refactoring fresh code is a design smell |

## The Bottom Line

Tests first. One step at a time. Commit after each step. Measure the improvement.

If you cannot explain what improved, you did not refactor. You just moved code around.
