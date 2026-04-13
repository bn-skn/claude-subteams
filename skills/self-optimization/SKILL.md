---
name: self-optimization
description: "Iterative improvement cycle for prompts, skills, and CLAUDE.md: identify problem, diagnose, edit, test, deploy."
---

# Self-Optimization

## 1. When to Trigger

1. A skill or prompt consistently produces suboptimal results.
2. User feedback indicates confusion or wrong outputs.
3. Prompt evaluation metrics show declining pass rate.
4. New requirements make existing prompts insufficient.
5. Monthly review cycle (scheduled maintenance).

## 2. Improvement Cycle

Follow this cycle strictly in order:

1. **Identify the problem** — What specific output is wrong or suboptimal? Collect 3+ examples.
2. **Diagnose root cause** — Is it a missing instruction? Ambiguous wording? Wrong constraint? Missing example?
3. **Propose edit** — Draft the specific change. Minimize blast radius — change as little as possible.
4. **Test** — Run prompt-evaluation skill with existing regression tests + new test for the identified problem.
5. **Deploy** — If tests pass, apply the edit. If tests fail, iterate from step 3.

## 3. Diagnosis Framework

| Symptom | Likely Root Cause | Fix Pattern |
|---------|-------------------|-------------|
| Output misses a step | Missing instruction | Add numbered step to checklist |
| Output includes wrong content | Ambiguous or missing constraint | Add NEVER/ALWAYS rule |
| Output format is wrong | Format spec is unclear | Add explicit example in the prompt |
| Agent does unnecessary work | Scope is too broad | Narrow the task description |
| Agent hallucinates facts | Missing research step | Add research-first instruction |
| Output is too verbose | No conciseness constraint | Add word/line limit |
| Output is inconsistent | No deterministic anchors | Add rigid format or template |

## 4. Edit Scope Rules

1. Change ONE thing per iteration. NEVER batch multiple unrelated fixes.
2. If the fix requires changing more than 10 lines, split into multiple iterations.
3. ALWAYS preserve existing passing behavior — optimization must not regress.
4. Prefer adding constraints over removing them.
5. Prefer making implicit rules explicit over restructuring.

## 5. Version Tracking

1. Before every edit, record: date, what changed, why, who triggered it.
2. Format:

```
## Change Log
- [DATE]: [WHAT changed] — [WHY] — triggered by [USER_FEEDBACK | METRIC_DECLINE | REVIEW]
```

3. Keep the change log in the same file or adjacent to the edited prompt/skill.
4. NEVER edit without adding a change log entry.
5. Review change log monthly to identify patterns (same area keeps breaking = deeper structural issue).

## 6. Applies To

This skill applies to optimization of:

1. **CLAUDE.md files** — root and subdirectory configuration.
2. **SKILL.md files** — any skill in the skills/ directory.
3. **Agent prompts** — subagent prompt templates and instructions.
4. **Hook configurations** — pre/post commit hooks, automation rules.

## 7. Monthly Review Checklist

1. Review every skill's prompt-evaluation metrics from the past month.
2. Identify skills with pass rate below 90%.
3. Identify skills that were not used at all — consider deprecating.
4. Check for duplicate or overlapping skills — merge if possible.
5. Verify all skills still align with current project conventions.
6. Delete any rules that duplicate Claude's default behavior.

## 8. Red Flags Table

| Rationalization | Why It Is Wrong | Correct Action |
|-----------------|-----------------|----------------|
| "I'll fix multiple things at once" | Cannot isolate which fix worked | One change per iteration |
| "No need to test, it's a small edit" | Small edits cause regressions | Always run regression tests |
| "I'll just rewrite the whole prompt" | Loses working parts | Minimal targeted edits |
| "The old version was fine, no need to log" | Change history prevents repeat mistakes | Always log changes |
| "This skill is rarely used, skip review" | Unused skills waste cognitive load | Deprecate or remove |

## 9. Critical Rules

1. NEVER skip the test step in the improvement cycle.
2. NEVER edit more than one thing per iteration without testing between edits.
3. ALWAYS record what changed and why before deploying.
4. MUST run prompt-evaluation after every edit.
5. NEVER delete a skill without checking if other skills or agents reference it.
