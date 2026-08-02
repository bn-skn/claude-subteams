---
name: delivering-to-user
description: "Use before an expensive delivery to a human — a client document, a rendered page or image, a generated asset, a diff, a report, or a subagent's output you are about to pass on. One deliberate pass as the recipient: right question answered, nothing invented, no internal scaffolding leaking, visual artifact actually viewed. Also covers progress signalling during long work. Raw handover is allowed when asked for it — but never unread, and broken output gets one line above it. Do NOT use it as a substitute for correctness verification (verification-gate) or independent review (code-review, cross-review)."
---

# Delivering to the User — The Recipient Pass

## 1. The Recipient Pass

1. Everything generated — text, image, code, document — gets ONE deliberate pass by you, as if you were the recipient reading it for the first time, BEFORE it is shown.
2. Read a subagent's or a generator's output before it goes to a human. Relaying is not delivering.
3. The recipient sees your name on it. Their reaction to sloppy output is to you, not to the tool that produced it.
4. The pass is cheap and takes seconds. Skipping it is how internal scaffolding, wrong-question answers, and broken artifacts reach a human.

## 2. What the Pass Checks

1. **Does it answer the question actually asked** — not an adjacent one you found more interesting?
2. **Is anything in it invented?** Facts you did not verify are labeled as unverified or removed.
3. **Is internal machinery leaking?** Agent chatter, scratch reasoning, TODO markers, placeholder text, template fragments — strip them.
4. **Is it complete?** Truncated output, an artifact referenced but not attached, a promise made and not fulfilled in the same message.
5. **Does the artifact itself look right?** If it renders (page, image, diagram, PDF), you must have looked at it — see `verification-gate`, Visual Verification.
6. **Is the register right for this recipient?** An internal note and a client-facing document are not the same document.

## 3. When the User Asks for the Raw Output

1. Handing over untouched output IS allowed when that is precisely what the person asked for ("send it raw", "don't rewrite it", "paste it as is"). Their explicit wish outranks your polish.
2. You still read it first. The pass is about YOUR knowledge of what you are handing over — it does not require you to alter a single character.
3. If the output is broken, empty, truncated, or contains an error message instead of a result, add ONE line above it saying so, then hand it over raw as asked.
4. Never promise not to read it. Agreeing to deliver blind is the one thing this skill forbids.

## 4. The Pass Is Not a Review

1. The recipient pass is self-review by the author — it catches leakage, incoherence, and wrong-target answers.
2. It does NOT replace independent review by a separate reviewer for significant work (`code-review`, `cross-review`).
3. It does NOT replace correctness verification (`verification-gate`). Order: verify it is TRUE → have it reviewed if significant → recipient pass → deliver.

## 5. Progress During Long Work

1. Silence during a multi-step task reads as a hang. Send progress through whatever notification channel the environment provides.
2. Signal at meaningful boundaries: stage completed, a blocker hit, a plan changed — not every tool call.
3. Fast tasks get NO progress messages. A ping followed one second later by the result is pure noise.
4. A blocker MUST be reported when it is hit, not disclosed at the end as part of the final report.

## 6. Red Flags

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| Pasting a subagent's report verbatim by default | Its format, verbosity, and internal jargon target you, not the recipient | Read it, extract the outcome, rewrite for the reader |
| Agreeing to forward output unread on request | "Raw" is about editing, not about blindness | Deliver it raw as asked — after reading it, flagging it if broken |
| Shipping a generated image or page unviewed | Broken renders survive every text-level check | Open it, look, then deliver |
| Delivering an artifact you know is truncated or errored | The recipient discovers the defect instead of you | One line stating the defect, above the artifact |
| Leaving TODO markers or placeholder text in a client document | Reads as unfinished work sent by accident | Strip internal scaffolding during the pass |
| Progress pings on a 10-second task | Trains the recipient to ignore your notifications | Report only on long work, at real boundaries |
| Silence for the whole of a long task | Indistinguishable from a crash | Signal at stage boundaries |

## 7. Critical Rules

1. NEVER deliver generated output you have not read yourself first.
2. NEVER agree to forward output unread, even when asked — reading it and handing it over unedited are compatible.
3. ALWAYS look at a visual artifact before claiming it is ready.
4. MUST flag broken, empty, or errored output in one line above it, including when delivering raw.
5. MUST report blockers when they occur, not in the final summary.
6. NEVER treat this pass as a substitute for independent review or verification.

## 8. Related Skills

- `verification-gate` — correctness and visual evidence; runs BEFORE the recipient pass.
- `code-review` / `cross-review` — independent review for significant work; this pass does not replace it.
- `orchestrator-briefing` § Mirror Principle — the subagent's self-check before returning to the orchestrator; this skill is the last step before a human. They do not replace each other.
- `context-gaps` — makes sure the answer is built on real context rather than an invented one.
