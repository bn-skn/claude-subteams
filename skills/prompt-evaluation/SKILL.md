---
name: prompt-evaluation
description: "Evaluate prompts and skills with representative test inputs, regression test cases, and pass/fail metrics."
---

# Prompt Evaluation

## 1. Test Input Creation

1. For every prompt or skill being evaluated, create 5-10 representative test inputs.
2. Inputs MUST cover: happy path (2-3), edge cases (2-3), adversarial/tricky inputs (1-2), empty/minimal inputs (1).
3. Each test input MUST have a corresponding expected output or acceptance criteria.
4. Document inputs in a structured format: input, expected output, rationale for inclusion.
5. NEVER test with only happy-path inputs — edge cases reveal real problems.

## 2. Test Execution Checklist

1. Run each test input through the prompt/skill exactly as a user would.
2. Capture the full output for each test.
3. Compare output against expected result.
4. Record result as: PASS (matches expected), FAIL (wrong output), PARTIAL (partially correct).
5. For FAIL and PARTIAL, note specifically what diverged from expected.
6. MUST run all test inputs — NEVER skip inputs that "probably work."

## 3. Regression Test Cases

1. After initial evaluation, save passing test cases as regression tests.
2. Store in a predictable location: `tests/` directory adjacent to the prompt/skill file.
3. Each regression test file MUST include: test name, input, expected output, date created.
4. Format: YAML or JSON, one file per prompt/skill.
5. NEVER delete regression tests unless the underlying requirement changed.

## 4. Re-run After Edits

1. After any edit to a prompt or skill, re-run ALL regression tests.
2. If any previously passing test now fails, the edit introduced a regression.
3. Regressions MUST be fixed before the edit is accepted.
4. If the edit intentionally changes behavior, update the affected test's expected output and document WHY.
5. NEVER merge an edit that breaks existing regression tests without explicit justification.

## 5. Metrics Tracking

1. Track pass/fail ratio for each evaluation run.
2. Track metrics over time: is the prompt improving or degrading?
3. Minimum acceptable pass rate: 80% for flexible skills, 95% for rigid skills.
4. Report metrics in this format:

```
PROMPT: [name]
RUN_DATE: [date]
TOTAL_TESTS: [N]
PASSED: [N]
FAILED: [N]
PARTIAL: [N]
PASS_RATE: [X%]
REGRESSIONS: [N new failures vs previous run]
```

## 6. Evaluation Criteria

For each test output, evaluate against these dimensions:

| Dimension | Weight | Check |
|-----------|--------|-------|
| Correctness | High | Does the output match the expected result? |
| Completeness | High | Are all required elements present? |
| Format compliance | Medium | Does the output follow the specified format? |
| Conciseness | Medium | Is the output appropriately brief, no filler? |
| Edge case handling | High | Does it handle unusual inputs gracefully? |
| Harmful outputs | Critical | Does it ever produce dangerous/incorrect advice? |

## 7. Dispatching to prompt-evaluator Agent

1. Use the prompt-evaluator agent (opus model) for automated evaluation.
2. Provide: the prompt/skill text, test inputs with expected outputs, evaluation criteria.
3. Agent tools: Read, Write, Bash, Grep, Glob.
4. Agent MUST return results in the standardized metrics format from section 5.

## 8. Critical Rules

1. NEVER ship a prompt edit without running regression tests.
2. NEVER evaluate with fewer than 5 test inputs.
3. ALWAYS include at least one adversarial test input.
4. MUST track metrics over time — single-run evaluation is insufficient.
5. NEVER accept a pass rate below 80% for any prompt or skill.
6. ALWAYS document why a test was added or modified.
