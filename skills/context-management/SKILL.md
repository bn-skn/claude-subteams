---
name: context-management
description: "Managing context window, checkpoints, and session summaries."
---

# Context Management — Checkpoints, Compaction, and Session Summaries

## 1. Convolife Monitoring

1. Be aware of your context window usage throughout the session.
2. As the conversation grows, you process more tokens per response — this slows down and increases cost.
3. Monitor for signs of context pressure: repeated information, long conversation history, many large file reads.

## 2. When to Create Checkpoints

Create a session summary checkpoint when ANY of the following occur:

1. A major task or milestone is completed.
2. A significant decision was made by the user.
3. The session is about to end (user says goodbye, wrapping up).
4. You have accumulated substantial context that would be lost.
5. Before a risky operation that might require session restart.

### Checkpoint Checklist

1. Summarize what was accomplished this session.
2. List all decisions made and their rationale.
3. List all files created or modified (with brief description of changes).
4. List pending tasks and next steps.
5. Note any blockers or open questions.
6. Save to a location the user can find (project root or docs/).

## 3. When to Compact

Compact the conversation when ANY of the following are true:

1. The conversation is getting noticeably long (many back-and-forth exchanges).
2. You notice yourself re-reading information you already processed.
3. Response times are slowing down.
4. The user explicitly asks to compact or summarize.

### Before Compacting

1. MUST create a checkpoint summary first — compaction loses detail.
2. MUST note all active file paths and their current state.
3. MUST preserve user decisions and constraints.
4. NEVER compact in the middle of an active task — finish or checkpoint first.

## 4. Session Summary Structure

When creating a session summary (for checkpoint or handoff), use this format:

```
## Session Summary — [DATE]

### Completed
- [Task 1]: brief description of what was done
- [Task 2]: brief description of what was done

### Decisions Made
- [Decision]: rationale (user chose X because Y)

### Files Modified
- `path/to/file.ts` — what changed
- `path/to/other.ts` — what changed

### Pending / Next Steps
- [ ] Task that still needs doing
- [ ] Another pending task

### Blockers / Open Questions
- Question that needs user input
- Issue that needs investigation

### Context for Next Session
- Key technical details the next session needs to know
- Active branch, plan location, relevant docs
```

## 5. Handoff to Future Sessions

1. Future sessions start with zero context — they know nothing about previous work.
2. A good session summary MUST be self-contained: a new agent should understand the project state from the summary alone.
3. Include file paths (absolute), branch names, plan locations.
4. Include WHY decisions were made, not just WHAT was decided.
5. NEVER assume the next session will "just know" — be explicit.

## 6. Red Flags Table

| Rationalization | Why It Is Wrong | Correct Action |
|-----------------|-----------------|----------------|
| "I'll remember this later in the session" | Context degrades as conversation grows | Write it down in a checkpoint |
| "No need to summarize, it's all in the chat" | Chat history becomes noise at scale | Create structured summaries |
| "I'll compact later" | Later means lost context | Compact proactively before pressure |
| "The next session will figure it out" | Next session has zero context | Write a complete handoff summary |
| "This detail is too minor to note" | Minor details cause major confusion later | Note all decisions and their rationale |

## 7. Critical Rules

1. NEVER compact without creating a checkpoint summary first.
2. NEVER end a productive session without offering to create a summary.
3. ALWAYS include file paths, branch names, and plan locations in summaries.
4. MUST preserve user decisions and their rationale across sessions.
5. ALWAYS structure summaries for a reader with zero prior context.
