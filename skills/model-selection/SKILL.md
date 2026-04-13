---
name: model-selection
description: "Guide for choosing sonnet vs opus for subagents."
---

# Model Selection — Sonnet vs Opus

## 1. General Rule

When uncertain which model to use — ALWAYS choose opus. The cost difference is small compared to the cost of a wrong result.

## 2. Sonnet — Simple, Routine, Low-Risk

Use sonnet when ALL of the following are true:

1. Task is straightforward with clear instructions.
2. No business logic or decision-making involved.
3. No cross-module impact.
4. Low risk if result is slightly wrong.

### Sonnet Examples

| Task | Why Sonnet |
|------|-----------|
| Doc formatting, README updates | No logic, low risk |
| Boilerplate generation (interfaces, types) | Template-driven, no decisions |
| Simple file edits (rename, move, update imports) | Mechanical, well-defined |
| CSS/styling changes | No business logic |
| Adding log statements | No logic impact |
| Generating changelog entries | Formatting task |

## 3. Opus — Complex, Important, or Uncertain

Use opus when ANY of the following are true:

1. Task involves business logic or algorithms.
2. Task involves architectural decisions.
3. Task involves security-sensitive code.
4. Task touches multiple files or modules.
5. Task requires understanding cross-module interactions.
6. Task involves debugging or investigation.
7. Task involves prompt or skill engineering.
8. You are not sure which model to use.

### Opus Examples

| Task | Why Opus |
|------|---------|
| Bug investigation and fix | Requires reasoning about cause and effect |
| API design, schema changes | Architectural decisions |
| Security audit, auth logic | Security-critical, high risk |
| Refactoring with behavior preservation | Must understand existing logic |
| Writing tests for complex logic | Must understand edge cases |
| Code review of logic changes | Must reason about correctness |
| Cross-module changes (3+ files) | Must understand interactions |
| Prompt/skill writing | Requires meta-reasoning |

## 4. Decision Tree

```
Is the task routine with zero logic?
├── YES → Does it touch only 1-2 files?
│         ├── YES → Is it low risk if slightly wrong?
│         │         ├── YES → sonnet
│         │         └── NO  → opus
│         └── NO  → opus
└── NO  → opus
```

## 5. Model Assignment by Default Agent

| Agent | Default Model | Override When |
|-------|--------------|---------------|
| code-reviewer | opus | Never — reviews require deep reasoning |
| test-engineer | opus | Never — adversarial testing requires creativity |
| architecture-guard | opus | Never — architecture requires holistic understanding |
| design-critic | opus | sonnet for simple a11y checks only |
| prompt-evaluator | opus | Never — meta-reasoning required |
| doc-agent | sonnet | opus if docs require technical accuracy review |
| researcher | opus | Never — research requires synthesis |
| security-auditor | opus | Never — security is always high-risk |
| devils-advocate | opus | Never — challenging assumptions requires deep reasoning |

## 6. Critical Rules

1. NEVER use sonnet for security-related tasks.
2. NEVER use sonnet for tasks involving business logic.
3. NEVER use sonnet for debugging or investigation.
4. ALWAYS default to opus when uncertain.
5. The orchestrator (you) ALWAYS runs on opus — never downgrade yourself.
