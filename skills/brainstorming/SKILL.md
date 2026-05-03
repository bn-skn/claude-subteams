---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation through structured interviewing."
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through structured interviewing — a phased dialogue that builds understanding incrementally.

The orchestrator conducts the interview directly (NOT a subagent). You are already in the conversation context with the user. A subagent with a clean context would waste time re-asking what you already know.

<HARD-GATE>
When the brainstorming skill is active: do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. The design can be brief for simple projects.
Note: This gate applies when brainstorming is invoked. The orchestrator (using-subteams) decides WHETHER to invoke brainstorming based on pipeline selection. Lightweight and Standard pipelines skip brainstorming entirely.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility, a config change — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but you MUST present it and get approval.

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — check files, docs, recent commits
2. **Offer visual companion** (if topic will involve visual questions) — this is its own message, not combined with a clarifying question. See the Visual Companion section below.
3. **Interview the user** — phased questioning to build full understanding (see Interview Process below)
4. **Propose 2-3 approaches** — with trade-offs and your recommendation
5. **Present design** — in sections scaled to their complexity, get user approval after each section
6. **"What If?" Challenge** — generate 5-10 "what if" questions about the design and present to the user (see below)
7. **Write design doc** — save to `docs/specs/YYYY-MM-DD-<topic>-design.md` and commit
8. **Spec self-review** — quick inline check for placeholders, contradictions, ambiguity, scope (see below)
9. **User reviews written spec** — ask user to review the spec file before proceeding
10. **Transition to implementation** — invoke claude-subteams:writing-plans skill to create implementation plan

## Interview Process

Brainstorming is a structured interview, not a questionnaire dump. Each phase builds on the previous one. New questions naturally arise from answers — this is expected and valuable.

### Phase 1: Purpose & Vision (2-3 questions)

Understand the WHY before the WHAT.

- What problem does this solve? Who is it for?
- What does success look like? How will you know it works?
- What triggered this — a pain point, an opportunity, a request?

### Phase 2: Context & Constraints (3-4 questions)

Now that you understand the goal, explore the boundaries.

- Technical constraints: stack, integrations, existing code to work with
- Scale expectations: users, data volume, frequency
- Timeline and priority: urgent fix or strategic investment?
- Dependencies: what does this depend on, what depends on it?

Questions in this phase are shaped by Phase 1 answers. If the user said "this is for internal use by 2 people," don't ask about scaling to millions.

### Phase 3+: Deepening (as many rounds as needed)

Each round of answers reveals new dimensions. Follow them.

- Clarify ambiguities from previous answers
- Explore edge cases that became apparent
- Dig into technical details relevant to the emerging design
- Challenge assumptions you're forming ("You mentioned X — does that mean Y?")

**There is no artificial limit on rounds.** Continue until you can confidently describe the task, its constraints, and success criteria. The stop criterion is quality of understanding, not number of questions asked.

**Degradation clause:** If after 3 rounds the interview is not converging (user gives vague answers, scope keeps shifting), summarize what you DO know, state your assumptions explicitly, present a best-effort design, and ask: "Should we continue refining or move forward with this?" The user can say "keep asking" — but the default is forward motion, not infinite loops.

### Interview Rules

1. **2-4 questions per round.** Enough to make progress, not so many that the user faces a wall of text.
2. **Multiple choice where possible.** "Do you want A, B, or C?" is easier to answer than "What approach do you prefer?" But use open-ended questions when you need depth.
3. **Build on answers.** Each round must reference what the user said previously. Never ask something you could infer from their prior answers.
4. **Read the codebase first.** NEVER ask questions you can answer by reading existing code, docs, or config. Research first, ask second.
5. **Flag scope issues early.** If the request describes multiple independent subsystems, flag this before diving into details. Decompose first, then interview per sub-project.
6. **Summarize understanding between phases.** After Phase 2 (and after Phase 3 if it goes multiple rounds), briefly state your current understanding: "So far I understand: [summary]. Is this right?" This prevents drift.

### When to Stop Interviewing

You are ready to move to approaches when you can answer ALL of these:

- [ ] What exactly are we building? (clear, specific, not vague)
- [ ] Why? What problem does it solve?
- [ ] For whom? Who uses this?
- [ ] What are the hard constraints? (tech stack, integrations, performance)
- [ ] What does "done" look like? (acceptance criteria)
- [ ] What is explicitly NOT in scope?

If you cannot confidently check all boxes — ask more questions. If you can — move to approaches.

## Exploring Approaches

- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

## Presenting the Design

- Once you believe you understand what you are building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something does not make sense

## "What If?" Challenge

After presenting the design and getting user approval on the sections, but BEFORE writing the spec, run a "What If?" challenge. Generate 5-10 probing questions about the design covering:

- **Scale:** What if this needs to handle 10x/100x the expected load?
- **Dependencies:** What if a key dependency becomes unavailable or changes its API?
- **Edge cases:** What if inputs are malformed, empty, enormous, or adversarial?
- **Necessity:** What if we removed this component entirely — would anything break?
- **Assumptions:** What if our core assumption about [X] is wrong?
- **Timing:** What if operations happen out of order or concurrently?
- **Failure modes:** What if [critical step] fails silently?
- **Integration:** What if the consuming system expects a different contract?
- **Migration:** What if we need to change this design 6 months from now?
- **Security:** What if an attacker targets this specific component?

Present these questions to the user. Discuss any that surface real concerns. Adjust the design if needed before writing the spec. This catches assumptions early and is cheaper than discovering them during implementation.

## Design for Isolation and Clarity

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently
- For each unit, you should be able to answer: what does it do, how do you use it, and what does it depend on?
- Smaller, well-bounded units are easier to work with — you reason better about code you can hold in context at once

## Working in Existing Codebases

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work, include targeted improvements as part of the design
- Do not propose unrelated refactoring. Stay focused on what serves the current goal.

## After the Design

**Documentation:**

- Write the validated design (spec) to `docs/specs/YYYY-MM-DD-<topic>-design.md` (create directory if it does not exist)
  - (User preferences for spec location override this default)
- Commit the design document to git

**Spec Self-Review:**

1. **Placeholder scan:** Any "TBD", "TODO", incomplete sections, or vague requirements? Fix them.
2. **Internal consistency:** Do any sections contradict each other? Does the architecture match the feature descriptions?
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition?
4. **Ambiguity check:** Could any requirement be interpreted two different ways? If so, pick one and make it explicit.

Fix any issues inline. No need to re-review — just fix and move on.

**User Review Gate:**

After the spec review loop passes, ask the user to review the written spec before proceeding:

> "Spec written and committed to `<path>`. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

Wait for the user's response. Only proceed once the user approves.

**Implementation:**

- Invoke the claude-subteams:writing-plans skill to create a detailed implementation plan
- Do NOT invoke any other skill. writing-plans is the next step.

## Key Principles

- **Interview, don't interrogate** — Build understanding through phased dialogue, not a question dump
- **Multiple choice preferred** — Easier to answer than open-ended when possible
- **No artificial limits** — Ask as many questions as needed for full understanding, but keep rounds focused (2-4 questions each)
- **YAGNI ruthlessly** — Remove unnecessary features from all designs
- **Explore alternatives** — Always propose 2-3 approaches before settling
- **Incremental validation** — Present design, get approval before moving on
- **Be flexible** — Go back and clarify when something does not make sense
- **Summarize often** — Reflect understanding back to the user to catch drift early

## Visual Content

When brainstorming involves visual questions (UI mockups, architecture diagrams, layout comparisons), use available tools:

- **Playwright browser** (if available via MCP) — render components, take screenshots, show mockups
- **Excalidraw diagrams** — architecture, data flow, system diagrams
- **Terminal** — for text-based questions (requirements, tradeoffs, scope decisions)

The test: **would the user understand this better by seeing it than reading it?** If yes — use a visual tool. If no — terminal is fine.
