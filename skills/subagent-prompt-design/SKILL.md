---
name: subagent-prompt-design
description: "Design subagent prompts with minimal context, restricted tools, standardized output, and explicit handoff protocols."
---

# Subagent Prompt Design

## 1. Tool Restriction

1. NEVER give a subagent all tools. Restrict to what the task actually requires.
2. Read-only tasks: Read, Grep, Glob only. No Write, no Edit, no Bash.
3. Implementation tasks: Read, Write, Edit, Bash, Grep, Glob.
4. Research tasks: Read, Grep, Glob, WebSearch, WebFetch.
5. ALWAYS list tools explicitly in the Agent tool call — never rely on defaults.
6. If a subagent needs a tool you did not grant, that is a prompt design error — redesign the task.

## 2. Context Minimization

1. Pass ONLY what the subagent needs to complete its task.
2. Include: task description, relevant file paths, constraints, expected output format.
3. NEVER dump the entire conversation history into a subagent prompt.
4. NEVER pass more than 10 file paths — if more are needed, pass a directory and let the agent search.
5. Summarize relevant background in 2-3 sentences, not full paragraphs.
6. MUST include any project-specific conventions that affect the task (e.g., naming rules, formatting).

## 3. Standardized Output Format

Every subagent MUST return results using the orchestrator-briefing output contract:

```
**Task:** brief description of what was done
**Status:** done | partial | blocked
**Rails read:** <path(s) read> — "<constraint quote>" applied at <file:line>

### Changes
- `path/to/file.ts` — what changed and why

### Verification
- tsc --noEmit: OK / FAIL
- Tests: OK / FAIL

### Questions (if any)
### Notes (if any)
```

1. Include this format specification in every subagent prompt.
2. NEVER accept free-form prose as the sole output from a subagent.
3. The **Status** field MUST always be present and MUST be one of: done, partial, blocked.
4. Changes MUST include file:line references when applicable.
5. This format matches the orchestrator-briefing skill — NEVER define a competing format.
6. Agent-local `## Output Contract` sections inherit the `Rails read:` line from this canonical contract — it arrives via the brief and does not need to be duplicated into each agent file.

## 4. Agent Chain Rules

1. NEVER create circular agent chains (A calls B calls A).
2. Linear chains are acceptable: A calls B, B returns to A, A calls C.
3. Maximum chain depth: 3 (orchestrator -> agent -> sub-agent). NEVER deeper.
4. If a task requires deeper nesting, restructure as parallel fan-out from orchestrator.
5. Each agent in a chain MUST have a distinct, non-overlapping responsibility.

## 5. Explicit Handoff Protocol

1. Before every Agent tool call, state WHO you are dispatching to and WHY.
2. Format: "Dispatching to [agent-name] to [specific task]. Reason: [why this agent, not doing it yourself]."
3. After receiving results, state what you learned and what you will do next.
4. NEVER silently consume agent output — always report key findings to the user.
5. If agent results are unclear or incomplete, ask the agent to retry with clarified instructions — do NOT guess.

## 6. Prompt Template

Use this template for every subagent prompt:

```
You are a [role]. Your task: [one-sentence description].

## Context
[2-3 sentences of relevant background]

## Files
[list of relevant file paths]

## Rails
[conventions/architecture docs and active plan the subagent must read before acting, when they exist]

## Constraints
[numbered list of rules and limitations]

## Output Format
**Task:** [what was done/found]
**Status:** done | partial | blocked
**Rails read:** [path — constraint applied]

### Changes
- [file:line — what changed]

### Verification
- [compilation/test results]

### Questions (if any)
### Notes (if any)
```

## 7. Red Flags Table

| Rationalization | Why It Is Wrong | Correct Action |
|-----------------|-----------------|----------------|
| "Give it all tools just in case" | Increases blast radius of errors | Restrict to needed tools |
| "It needs the full conversation context" | Wastes tokens, confuses the agent | Summarize in 2-3 sentences |
| "I'll just read the prose output" | Unstructured output is hard to act on | Require standardized format |
| "Agent A can call Agent B can call Agent C can call..." | Deep nesting is fragile and expensive | Max depth 3, prefer fan-out |
| "I'll dispatch without explaining why" | Loses traceability for debugging | Always state WHO and WHY |

## 8. Critical Rules

1. NEVER grant Write/Edit tools to a read-only review agent.
2. NEVER skip the output format specification in the prompt.
3. ALWAYS validate the **Status** field exists in agent output before proceeding.
4. MUST include the handoff statement before every Agent tool call.
5. NEVER spawn a subagent for a task that would take you less than 30 seconds.

## 9. Specialist Agent

For authoring or optimizing a subagent's prompt at quality, dispatch the **prompt-engineer** agent (opus) — it applies this skill's rules (tool restriction, context minimization, output contract) to produce the wording, then hands off to **prompt-evaluator** for validation. See `using-subteams` Section 6.5. Use `agent-architect` first when the agent's boundaries and topology are not yet decided.
