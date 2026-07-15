---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. Adversarial testing (default) or TDD (optional, user choice). Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they do not know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If using the Full pipeline, create a feature branch (or worktree for parallel work) before writing code.

**Save plans to:** `docs/plans/active/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

**Contract artifact (two weights):** if any risk-trigger fires (using-subteams §6) or a single feature spans multiple sessions, author a **light contract** (`docs/plans/active/IMPL-PLAN-<slug>.md`: scope / acceptance criteria / non-goals) per the `living-plan` skill. Escalate to the **full package → criterion matrix** only for multi-package (≥2) or TZ-with-acceptance work. A risk-trigger mandates the artifact, not a deeper pipeline; trivial single-session work gets nothing.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it was not, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

1. Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
2. You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
3. Files that change together should live together. Split by responsibility, not by technical layer.
4. In existing codebases, follow established patterns. If a file you are modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Testing Strategy

**Default: Adversarial testing** — write implementation first, then write tests that actively try to break it. Focus on edge cases, boundary conditions, error paths, and unexpected inputs. The goal is to find bugs, not confirm happy paths.

**Optional: TDD** — if the user explicitly requests TDD, follow the red-green-refactor cycle: write the failing test first, implement minimal code to pass, then refactor. Only use TDD when the user asks for it.

In both approaches, every task MUST include test steps with complete test code.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the implementation code" - step
- "Run it to verify it compiles/loads" - step
- "Write the adversarial tests" - step
- "Run tests and verify they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use claude-subteams:subagent-driven-dev (recommended) or claude-subteams:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 2: Verify it compiles/loads**

Run: `python -c "from module import function"`
Expected: No errors

- [ ] **Step 3: Write adversarial tests**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected

def test_edge_case_empty_input():
    with pytest.raises(ValueError):
        function("")

def test_boundary_condition():
    result = function(MAX_VALUE)
    assert result == expected_boundary
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/path/test.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## No Placeholders

Every step MUST contain the actual content an engineer needs. These are **plan failures** — NEVER write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Risks & Nuances Section (Mandatory)

Every plan MUST include a Risks & Nuances section after the task list:

```markdown
## Risks & Nuances

### Known Risks
- [Risk]: Description, probability (low/medium/high), impact, mitigation

### Non-Obvious Behavior
- [Nuance]: What might surprise the implementer or reviewer

### Dependencies
- [Dep]: What this feature depends on, what depends on it, migration concerns

### Rollback Plan
- How to revert if things go wrong (git revert, data migrations, API contracts, external state)
```

If you cannot identify ANY risks — you have not thought hard enough. Re-read the plan and consider: what if the network is down? What if the data is malformed? What if two users do this simultaneously? What if the dependency changes its API?

## Optional Sections (risk-triggered — not default ceremony)

Three sections are added to the plan ONLY when a specific risk-trigger fires. They are not written by default: a change that is not user-facing, touches no schema, and adds no API gets **none** of them. Do not pad a plan with empty stubs — omit the section entirely when its trigger is absent.

- **`## User Stories`** — write when the feature is **user-facing**. One story per user-visible behavior: `As <role>, I want <action>, so that <value>`, each with its own acceptance criterion. This section doubles as the test spec: the ui-tester reads it as scenarios in its default (scenario) mode, so vague stories produce vague tests.
- **`## Data Design`** — write when the change **alters the database schema**. Cover affected tables/fields, indexes, and the migration (forward + rollback). Follow the `database-design` skill for modeling guidelines.
- **`## Interface Contract`** — write when the change **introduces or changes a public API**. Reference the contract in `docs/openapi.yaml` (the source of truth), and follow the `api-design` skill. Do not restate the whole spec inline — link it.

When in doubt **about the trigger itself** — is this feature user-facing? does this change touch the schema? — treat that one section as required (the same bias-toward-review the pipeline uses). General uncertainty about the task is NOT a trigger and never justifies adding all three. Never invent a trigger to justify a section the task does not need.

## Remember
- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, adversarial testing by default, frequent commits

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

- [ ] Risk-triggered sections present where their trigger fired: user-facing → `## User Stories` (each story has its acceptance line), schema change → `## Data Design`, new/changed public API → `## Interface Contract`. And absent where no trigger fired — empty stubs are worse than nothing.

1. **Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.
2. **Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.
3. **Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, offer execution choice:

**"Plan complete and saved to `docs/plans/active/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use claude-subteams:subagent-driven-dev
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use claude-subteams:executing-plans
- Batch execution with checkpoints for review
