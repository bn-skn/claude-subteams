---
name: orchestrator-briefing
description: "Subagent communication protocol. Use before any Agent tool call."
type: rigid
---

# Orchestrator Briefing — Subagent Communication Protocol

## 1. Core Principle

Subagents are **smart AI agents**, not dumb executors. They can think, research, ask questions, and use any tools you grant them. Your job is to give them the right tools and enough context to work independently.

## 2. Two-Pass Protocol

1. **Pass 1:** Send full brief. Subagent works and returns result.
   - If subagent has enough context — result is final (done).
   - If subagent needs clarification — it returns questions in the Questions section.
2. **Pass 2:** Send a NEW brief (original + answers to questions) to a FRESH subagent instance. Returns result.
3. **Pass 3 (rare):** One more re-brief if orchestrator judges it worthwhile. Max 3 passes total.

### Critical Rules for Multi-Pass

1. NEVER send a follow-up message. Subagents have NO persistent context. Each call starts from scratch.
2. ALWAYS re-send the FULL brief with additional context — not a delta.
3. Do NOT force subagents to ask questions. Simply tell them: "if something is unclear, return your questions in the Questions section."
4. MUST ask clarifying questions to the USER before delegating when requirements are ambiguous — you are the leader who coordinates, not a relay.

## 3. Tool Allocation by Role

| Role | Tools | Access Level |
|------|-------|-------------|
| Code reviewer | Read, Grep, Glob, Bash | Read-only |
| Developer | Read, Write, Edit, Bash, Grep, Glob | Full |
| Test engineer | Read, Write, Edit, Bash, Grep, Glob | Full |
| Researcher | Read, Grep, Glob, WebSearch, WebFetch | Read + web |
| Architecture guard | Read, Grep, Glob, Bash | Read-only |
| Design critic | Read, Grep, Glob, Bash | Read-only |
| Doc agent | Read, Write, Edit, Grep, Glob | Full (no Bash) |
| Security auditor | Read, Grep, Glob, Bash | Read-only |

## 4. Input Format (Orchestrator to Subagent)

ALWAYS structure your brief with these sections:

```
Task: What to do (clear, specific, actionable)
Context: Why this task exists, user decisions, constraints
Files: Specific paths and line numbers to work with
Scope: What to do AND what NOT to do
Model: sonnet or opus (default: opus when uncertain)
Tools: What tools you have access to
```

### Input Checklist

1. MUST specify concrete file paths and line numbers — not "the auth module."
2. MUST pass user decision context — subagent cannot read conversation history.
3. MUST define scope explicitly — what to do AND what NOT to do.
4. MUST list tools the subagent can use.
5. NEVER assume the subagent knows anything about the conversation.
6. Brief like a colleague who just walked in — full context, zero assumptions.

## 5. Output Contract (Subagent to Orchestrator)

Every subagent MUST return this structure:

```
**Task:** brief description of what was done
**Status:** done | partial | blocked

### Changes
- `path/to/file.ts` — what changed and why

### Verification
- tsc --noEmit: OK / FAIL
- Tests: OK / FAIL
- Lint: OK / FAIL (if applicable)

### Questions (if any)
- Questions the subagent could not resolve independently

### Notes (if any)
- Observations, risks, suggestions for orchestrator
```

## 6. File Conflict Prevention for Parallel Dispatch

1. NEVER assign overlapping file sets to parallel subagents.
2. Before parallel dispatch, list all files each subagent will touch.
3. If files overlap — serialize those tasks or split into non-overlapping sets.
4. When possible, use git worktrees for parallel work isolation.
5. After parallel dispatch, check for conflicts before proceeding.

### Parallel Dispatch Checklist

1. List all tasks and their file dependencies.
2. Verify no two parallel tasks touch the same file.
3. If overlap exists — either serialize or split files.
4. Dispatch all independent tasks in ONE message (multiple Agent tool calls).
5. After all return — verify, integrate, resolve any conflicts.

## 7. Red Flags Table

| Rationalization | Why It Is Wrong | Correct Action |
|-----------------|-----------------|----------------|
| "The subagent will figure it out" | Vague briefs produce vague results | Be specific: files, lines, scope |
| "I'll just forward the user's message" | Subagent has no conversation context | Write a proper brief with full context |
| "No need to verify, the subagent is smart" | Smart agents still hallucinate | Read every changed file yourself |
| "I'll send a follow-up to clarify" | Subagents are stateless — follow-ups are lost | Re-send full brief with clarification |
| "Both subagents can edit that file" | Parallel edits cause conflicts | Non-overlapping file sets only |
