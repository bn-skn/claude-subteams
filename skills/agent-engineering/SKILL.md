---
name: agent-engineering
description: "Design multi-agent systems: orchestrator + specialists pattern, context engineering, token efficiency, and standardized contracts."
---

# Agent Engineering

## 1. Core Principle

1. Context engineering is more important than prompt engineering.
2. What you put INTO the agent's context determines output quality more than how you phrase instructions.
3. Give agents the right information, the right tools, and clear boundaries.
4. NEVER optimize wording before optimizing context.

## 2. Orchestrator + Specialists Pattern

1. Use one orchestrator agent that understands the full task and delegates.
2. Specialists handle one well-defined subtask each.
3. Fan-out: orchestrator dispatches to multiple specialists in parallel when tasks are independent.
4. Fan-in: orchestrator collects results, synthesizes, and makes final decisions.
5. NEVER let specialists talk to each other directly — all communication flows through the orchestrator.
6. The orchestrator MUST understand results deeply enough to catch specialist errors.

## 3. Agent Boundaries

1. Agent boundaries MUST align with task boundaries.
2. One agent = one coherent task with clear inputs and outputs.
3. If an agent needs context from another agent's work, that context flows through the orchestrator.
4. NEVER create an agent for a task that takes less than 30 seconds to do directly.
5. NEVER create an agent that needs to modify files across multiple unrelated modules — split into per-module agents.

## 4. Token Efficiency

1. Minimize context window usage — every token costs latency and money.
2. Pass file paths, not file contents, when the agent has Read access.
3. Summarize conversation history in 2-3 sentences instead of passing raw history.
4. Use the smallest capable model: sonnet for simple tasks, opus for complex reasoning.
5. Set clear stopping criteria — agents that run too long waste tokens.
6. NEVER pass entire codebases as context. Pass specific files or directories.

## 5. Model Selection Guide

| Task Type | Model | Rationale |
|-----------|-------|-----------|
| Code review, architecture analysis | opus | Requires deep reasoning |
| Documentation updates | sonnet | Straightforward, low complexity |
| Security audit | opus | Requires careful analysis |
| Test writing | opus | Requires understanding of edge cases |
| File formatting, renaming | sonnet | Mechanical, low reasoning |
| Research, investigation | opus | Requires synthesis of multiple sources |
| Simple search and report | sonnet | Low complexity gathering |

## 6. Standardized Agent Contract

Every agent MUST have:

1. **Frontmatter** — name, description, model, tools list.
2. **System prompt** — role, task, constraints, output format.
3. **Output format** — standardized structure matching orchestrator-briefing: Task, Status, Rails read, Changes, Verification, Questions, Notes.
4. NEVER create an agent without all three components defined.

```
## Agent Contract Template
Name: [agent-name]
Model: [opus | sonnet]
Tools: [explicit list]
Task: [one sentence]
Input: [what the orchestrator provides]
Output: [Task, Status (done|partial|blocked), Rails read, Changes, Verification, Questions, Notes]
```

## 7. Logging and Debugging

1. Log every agent dispatch: who was called, with what input, at what time.
2. Log every agent result: status, summary, duration.
3. When an agent fails, log: the prompt sent, the output received, the failure reason.
4. Use these logs to diagnose patterns: which agents fail most? On what inputs?
5. NEVER silently swallow agent errors — always surface them to the orchestrator.

## 8. Anti-Patterns

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| "One mega-agent that does everything" | Too much context, poor focus | Split into orchestrator + specialists |
| "Agents talk to each other" | Uncontrollable, hard to debug | All communication through orchestrator |
| "Pass entire codebase as context" | Token waste, dilutes relevant info | Pass specific file paths |
| "Use opus for everything" | Expensive and slow for simple tasks | Match model to task complexity |
| "Agent failed, retry immediately" | Same input = same failure | Diagnose first, then fix and retry |
| "Skip logging, it's extra work" | Cannot debug agent failures | Log every dispatch and result |
| "This needs 5 levels of agents" | Deep nesting is fragile | Max 3 levels, prefer flat fan-out |

## 9. Orchestration Checklist

Before dispatching any agent:

1. Define the task in one sentence.
2. List the specific files or directories the agent needs.
3. Choose the model based on task complexity (section 5).
4. Restrict tools to what the task requires.
5. Specify the expected output format.
6. Set a stopping criterion (max files to read, max iterations, etc.).
7. State the handoff: WHO and WHY.

## 10. Critical Rules

1. NEVER let specialists communicate directly — orchestrator mediates all.
2. NEVER pass raw conversation history to agents — summarize.
3. ALWAYS use the standardized output format from orchestrator-briefing (Task, Status, Rails read, Changes, Verification, Questions, Notes).
4. MUST log every agent dispatch and result for debugging.
5. NEVER nest agents deeper than 3 levels.
6. ALWAYS match model selection to task complexity.

## 11. Specialist Agents

This skill is the rulebook. For execution, dispatch the specialists (see `using-subteams` Section 6.5):

1. **agent-architect** — applies this methodology to design a subagent or multi-agent system (boundaries, topology, tool scoping, contracts). Dispatch whenever a new agent or system is created or restructured.
2. **prompt-engineer** — authors and optimizes the system-prompt wording once the structure is designed (see `subagent-prompt-design`).
3. **prompt-evaluator** — validates the designed agent/prompt against test inputs before shipping (see `prompt-evaluation`).

Division of labour: agent-architect owns structure and context; prompt-engineer owns wording; prompt-evaluator owns proof. Author → evaluate → iterate.
