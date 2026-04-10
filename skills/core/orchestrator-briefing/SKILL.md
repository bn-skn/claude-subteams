---
name: orchestrator-briefing
description: "Subagent communication protocol. Use before any Agent tool call."
type: rigid
---

# Orchestrator Briefing — Subagent Communication Protocol

## Why Briefing Quality Matters

A subagent sees NOTHING from your conversation. Your brief IS their entire world.

Every piece of context you omit is context they will hallucinate. Every ambiguity you leave is a decision they will make wrong. Every file path you skip is a file they will guess at. The quality of a subagent's output is directly proportional to the quality of your brief — never the subagent's capability.

**The briefing is not overhead. The briefing IS the work.** A 5-minute brief saves 30 minutes of rework. A lazy brief produces lazy results, and then you waste two more passes fixing what should have been right the first time.

Think of it this way: you are writing instructions for a brilliant colleague who just walked into the building for the first time today. They know nothing about your project, your conversation, your user's preferences, or your codebase. They CAN figure things out — but only if you tell them where to look and what matters.

## Complete Brief Template

ALWAYS structure your brief with ALL of these sections. Missing sections produce missing results.

```
Task: [specific, actionable — what exactly to do]
Context: [why we're doing this, what the user decided, constraints]
Files: [exact paths with line numbers where relevant]
Scope: [what to do AND what NOT to do]
Model: [sonnet/opus — with justification]
Tools: [exact list of tools granted]
```

### Example: Good Brief

```
Task: Add input validation to the createUser use case. Validate email format,
password strength (min 8 chars, 1 uppercase, 1 number), and username uniqueness.
Return structured validation errors, not exceptions.

Context: User reported that invalid emails pass through and create broken records.
We use Zod for validation elsewhere in the project (see src/shared/validation.ts).
The user explicitly decided against throwing exceptions — they want a Result type
pattern matching src/shared/result.ts.

Files:
- src/application/use-cases/create-user.ts (lines 12-45 — the execute method)
- src/domain/entities/user.ts (lines 1-30 — User entity, needs email/password types)
- src/shared/validation.ts (reference — existing Zod patterns)
- src/shared/result.ts (reference — Result type to follow)

Scope:
- DO: Add Zod schemas for email, password, username
- DO: Return Result<User, ValidationError[]> from execute method
- DO: Add unit tests for each validation rule
- DO NOT: Change the User entity constructor signature
- DO NOT: Modify the UserRepository interface
- DO NOT: Add new dependencies — use existing Zod

Model: sonnet — mechanical implementation with clear spec and patterns to follow

Tools: Read, Write, Edit, Bash, Grep, Glob
```

### Example: Bad Brief (and why)

```
Task: Fix the validation bug in user creation.
```

This brief fails on every dimension:
- **No context:** What bug? What symptoms? What did the user report?
- **No files:** Which file? Which function? What line?
- **No scope:** Should they refactor? Add tests? Change the API?
- **No model justification:** Defaulting to opus wastes money on a mechanical task.
- **No tools:** Subagent doesn't know what it can use.

The subagent will spend half its context window reading files trying to find "the bug," may fix the wrong thing, and will likely touch files you didn't want changed.

## Brief Anti-Patterns

### Anti-Pattern 1: The Vague Handoff

```
BAD:  "Fix the bug in auth"
GOOD: "Fix the login failure when email contains '+' characters.
       The issue is in src/infrastructure/auth/email-parser.ts line 23 —
       the regex doesn't handle '+' in the local part. Add a test case."
```

**Why it fails:** "Fix the bug" forces the subagent to spend 80% of its time finding the bug instead of fixing it. You already know where it is — say so.

### Anti-Pattern 2: The Context Dump

```
BAD:  [Forwards entire 200-message conversation to subagent]
GOOD: [Extracts the 3 relevant decisions and 5 relevant file paths]
```

**Why it fails:** Subagents have limited context. Dumping everything buries the signal in noise. The subagent may latch onto an early discussion point that was later overridden.

### Anti-Pattern 3: The Unbounded Task

```
BAD:  "Implement the payment module"
GOOD: "Implement the createPayment use case. It should call Stripe's
       PaymentIntents API, handle 3 error cases (card_declined,
       insufficient_funds, processing_error), and return a PaymentResult.
       Do NOT implement webhooks, refunds, or subscription logic."
```

**Why it fails:** Without scope boundaries, the subagent will add features you didn't ask for, touch files you didn't expect, and produce work that conflicts with your plan for other tasks.

### Anti-Pattern 4: The Relay

```
BAD:  "The user said 'make it work with PostgreSQL'"
GOOD: "Migrate the repository layer from SQLite to PostgreSQL.
       Current repo: src/infrastructure/repositories/sqlite-user-repo.ts.
       Target: create src/infrastructure/repositories/pg-user-repo.ts.
       Use the pg library (already in package.json). Connection config
       is in src/infrastructure/config/database.ts. Keep the same
       UserRepository interface from src/application/ports/user-repo.ts."
```

**Why it fails:** You are the orchestrator, not a message relay. Your job is to translate user intent into actionable specifications.

## Two-Pass Protocol

### Pass 1: Initial Dispatch

Send the full brief. The subagent works and returns a result using the output contract.

- If the result is complete and correct — done. Move on.
- If the subagent returned questions in the Questions section — proceed to Pass 2.

### Pass 2: Re-Brief with Answers

Create a NEW brief from scratch. Include:
1. The original task, context, files, scope (full — not a delta)
2. Answers to every question the subagent asked
3. Any additional context you realized was missing

Send this to a FRESH subagent instance. The previous instance is gone.

### Pass 3 (rare): Final Attempt

If Pass 2 still produced questions or incomplete results, you may do one more re-brief. After Pass 3, if the task is still not resolved, the problem is likely in your brief or the task decomposition — not the subagent. Re-think the task.

### Critical Rules

1. **NEVER send a follow-up message.** Subagents have NO persistent context. Each call starts from scratch. A "follow-up" goes to a new instance that has never seen your first message.
2. **ALWAYS re-send the FULL brief** with additional context — never send just the delta.
3. **Do NOT force subagents to ask questions.** Simply include: "If something is unclear, return your questions in the Questions section."
4. **MUST ask clarifying questions to the USER** before delegating when requirements are ambiguous. You are the leader who coordinates, not a relay that forwards confusion.

### Example Two-Pass Dialogue

```
--- Pass 1 ---
Orchestrator sends brief:
  Task: Implement rate limiting middleware for the API.
  Context: We need to limit requests per IP. No specific numbers decided yet.
  Files: src/presentation/middleware/ (create new file here)
  ...

Subagent returns:
  Status: blocked
  Questions:
  - What rate limit? (requests per minute/hour?)
  - Should limits differ per endpoint?
  - What response code for rate-limited requests? (429? 503?)

--- Orchestrator asks USER ---
Orchestrator: "The rate limiting task needs decisions:
  1. What rate limit per IP?
  2. Same limit for all endpoints or different?
  3. Response code when limited?"

User: "100 req/min for all endpoints, 429 response."

--- Pass 2 ---
Orchestrator sends NEW full brief:
  Task: Implement rate limiting middleware — 100 requests per minute per IP,
        uniform across all endpoints. Return 429 with Retry-After header.
  Context: [full context from Pass 1 + user's answers]
  Files: [same files + any new references]
  ...

Subagent returns:
  Status: done
  Changes: [list of changes]
```

## Tool Allocation by Role

Grant the MINIMUM tools needed. Fewer tools = more focused subagent.

| Role | Tools | Access Level | When to Use |
|------|-------|-------------|-------------|
| Code reviewer | Read, Grep, Glob, Bash | Read-only | PR reviews, architecture checks |
| Developer | Read, Write, Edit, Bash, Grep, Glob | Full | Feature implementation, bug fixes |
| Test engineer | Read, Write, Edit, Bash, Grep, Glob | Full | Test creation, test fixes |
| Researcher | Read, Grep, Glob, WebSearch, WebFetch | Read + web | Technology evaluation, docs lookup |
| Architecture guard | Read, Grep, Glob, Bash | Read-only | Dependency checks, layer violations |
| Design critic | Read, Grep, Glob, Bash | Read-only | API design review, naming review |
| Doc agent | Read, Write, Edit, Grep, Glob | Full (no Bash) | Documentation writing |
| Security auditor | Read, Grep, Glob, Bash | Read-only | Vulnerability scanning, auth review |
| Refactor agent | Read, Write, Edit, Bash, Grep, Glob | Full | Code restructuring, splitting files |

**Why no Bash for doc agents:** Documentation agents should not run commands. They read code and write docs. Bash access tempts them to run builds or tests, which is outside their role.

**Why Read-only for reviewers:** Reviewers that can edit will fix things instead of reporting them. You want reports, not silent fixes you can't review.

## Output Contract (Subagent to Orchestrator)

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

**Include this output contract template in every brief** so the subagent knows what format you expect.

## File Conflict Prevention for Parallel Dispatch

Parallel subagents are powerful but dangerous. One file edited by two subagents = guaranteed conflict.

### Rules

1. **NEVER assign overlapping file sets to parallel subagents.**
2. Before parallel dispatch, explicitly list ALL files each subagent will touch.
3. If files overlap — serialize those tasks or split into non-overlapping sets.
4. Shared read-only files are fine — only WRITE conflicts matter.
5. After parallel dispatch, check for conflicts before proceeding.
6. When possible, use git worktrees for parallel work isolation.

### Parallel Dispatch Checklist

1. List all tasks and their file dependencies (read AND write).
2. Build a file-to-task matrix. Verify no two parallel tasks WRITE to the same file.
3. If overlap exists — either serialize the overlapping tasks or split files.
4. Dispatch all independent tasks in ONE message (multiple Agent tool calls).
5. After all return — verify, integrate, resolve any conflicts.

### Example: Safe Parallel Split

```
Task A (Developer): Implement UserService
  WRITES: src/application/user-service.ts, src/application/user-service.test.ts
  READS:  src/domain/user.ts, src/application/ports/user-repo.ts

Task B (Developer): Implement OrderService
  WRITES: src/application/order-service.ts, src/application/order-service.test.ts
  READS:  src/domain/order.ts, src/application/ports/order-repo.ts

Overlap check: No write conflicts. Dispatch in parallel. SAFE.
```

## Mirror Principle — Self-Check Before Returning

Every subagent MUST verify its own work before returning results. If you find a problem — **fix it yourself**, don't return broken work.

1. **Re-read** every file you created or modified — does it match the brief?
2. **Run compilation** check if applicable (tsc, mypy, go build).
3. **Check references** — all referenced files, functions, and paths actually exist.
4. **Verify imports** — no circular dependencies, no missing modules.
5. **If anything is wrong — fix it.** Re-read again after fixing. Iterate until clean.
6. Only THEN return the result to orchestrator.

The "mirror principle": reviewing your own output before submitting it dramatically reduces rework cycles. It applies to everything — code, docs, configs, prompts.

**NEVER return work you know is broken.** Fix it first. If you genuinely cannot fix it — explain what's wrong and why in the Notes section, but don't silently pass broken output.

**Include this instruction in EVERY subagent brief:**
> "Before returning: re-read every changed file, run compilation, verify all paths exist. If you find problems — fix them yourself and re-check. Do not return broken work."

## Nuances Documentation

After any implementation, BOTH subagent and orchestrator capture nuances — things that work but have caveats, workarounds, known limitations, performance constraints, hardcoded values, temporary solutions.

**Subagent:** Flags nuances in the "Notes" section of the output contract.

**Orchestrator:** Reviews subagent notes and adds any they missed. Appends to the plan or CHANGELOG.

**Format:**
```markdown
### Implementation Nuances
- `path/to/file.ts:42` — hardcoded timeout (300ms) because API doesn't support configurable timeouts
- `path/to/handler.ts` — works for <1000 records, pagination needed for larger datasets
- Workaround: using `any` cast at line 78 due to library type bug (tracked: github.com/lib/issue/123)
```

**Why this matters:** Nuances are invisible technical debt. If you don't write them down at implementation time, they become mystery bugs 3 months later. The subagent that implemented the code is the best source — they saw the tradeoffs firsthand.

## Red Flags Table

| Rationalization | Why It Is Wrong | Correct Action |
|-----------------|-----------------|----------------|
| "The subagent will figure it out" | Vague briefs produce vague results | Be specific: files, lines, scope |
| "I'll just forward the user's message" | Subagent has no conversation context | Write a proper brief with full context |
| "No need to verify, the subagent is smart" | Smart agents still hallucinate | Read every changed file yourself |
| "I'll send a follow-up to clarify" | Subagents are stateless — follow-ups go to a new instance | Re-send full brief with clarification |
| "Both subagents can edit that file" | Parallel edits cause merge conflicts | Non-overlapping write sets only |
| "I'll just tell it to fix the bug" | No files, no context, no scope — guaranteed rework | Specify exact file, line, symptom, expected behavior |
| "I'll give it all the files" | Context overload buries the signal | Curate: only files relevant to the task |
| "It should figure out the context from the code" | Reading code is not the same as knowing intent | State the WHY, not just the WHERE |
| "I'll skip the scope section, it's obvious" | Nothing is obvious to an agent with zero context | Explicit scope prevents scope creep |
| "One big task is faster than three small ones" | Big tasks produce big mistakes | Decompose until each task is clear and testable |
