---
name: context-gaps
description: "Use when the user refers to something as already known — a project, a decision, an agreement, a module — and it is NOT in your context. Classify the gap (shared past / code / outside world), pull from the matching source, and never merge similar-but-different recall hits. Do NOT use for small talk, opinions, continuation of an already-loaded topic, or a request that arrives with full context."
---

# Context Gaps — Notice What You Are Missing, Fetch From the Right Source

## 1. The Trigger Is a Felt Gap, Not a Keyword

1. Automatic memory injection and keyword-based recall are background noise-catchers — they catch explicit "remember when we…" phrasing and miss everything else.
2. They MISS indirect references: "that project", "our contract", "the way we did it last time", "you already know about this".
3. The real trigger is the feeling: the user speaks about something as established, and your context (session, injected memory, loaded files) does not contain it.
4. On that signal: STOP. Do not invent, do not answer by guess, do not silently substitute a plausible-sounding fact.
5. Instead, do ONE deliberate step: identify the TYPE of gap, then fetch from the source that owns that type.
6. Fetching is not free — apply the calibration in §4 before spending a source.

## 2. Classify, Then Fetch

| Gap type | Looks like | Fetch from | NEVER do |
|----------|-----------|------------|----------|
| **Shared past** | Prior sessions, past decisions, agreements, facts about the user, their projects, their people | Long-term memory store + curated knowledge base, in that order | Web-search it. Your history with the user is not on the internet |
| **Code / this system** | How a module works, where a symbol is defined, blast radius, current config | The source itself: read files, grep, code index, a code-reading subagent | Answer from memory of the codebase. Memory of code is stale by construction |
| **Outside world** | Current facts, versions, prices, comparisons, news, an unfamiliar external API | One targeted web query first; deep research only if the single query is insufficient | Open a deep-research pipeline for a question one query would settle |

1. **Shared past — do not stop at the first miss.** Recall is lexically biased. Run 3–5 semantic variations of the query (synonyms, the English and the native term, key names, the technical label) before concluding anything.
2. **A dependency already installed in the project is CODE, not the outside world.** Read the installed package and its pinned docs. Go outside only for what does not exist in the project.
3. **Outside-world fetching composes with, and does not replace, `live-research`** (API currency before coding) and `systematic-debugging` (the research step of a bug hunt). Those protocols keep their own triggers.

## 3. Double Gaps

1. "Finish that parser we discussed" is TWO gaps: which parser and what was decided (shared past), plus what the code currently does (code).
2. Fetch both. **Memory first** — it tells you which code to go read.
3. Reversing the order wastes a code search on the wrong module.

## 4. Calibration — Against False Positives

1. This router is for a real gap, not for every message.
2. Answer immediately, fetching nothing, when: it is small talk, an opinion request, a continuation of an already-loaded topic, or a task that arrived with full context in the window.
3. Spend the EXPENSIVE source (deep research, multi-agent search) only when the answer would otherwise be a guess.
4. An unfamiliar word is not automatically an outside-world gap — first check whether it is an internal term of yours or the user's (memory / knowledge base), THEN consider the web.
5. When unsure whether a gap exists, resolve toward the CHEAP source: memory and knowledge base cost less than the web.

## 5. Similar-Looking Results Are Not One Fact

1. When recall returns several hits that are close in wording but divergent in substance — two people, two contracts, two projects with similar names — NEVER merge them into one answer.
2. Separate them first. If the divergence changes the answer and the user's phrasing does not disambiguate, ask ONE targeted question ("is this about X or about Y?").
3. Where both branches are useful, show them explicitly and answer per branch instead of asking.
4. Silently blending similar-by-words but different-by-substance is the worst memory failure mode: swapped account details, swapped people, swapped deal terms — quiet misinformation nobody catches.
5. Calibration: clarify ONLY when the ambiguity actually changes the answer. Hits about the same thing, or already disambiguated by context, get answered straight — do not interrogate over trivia.
6. The risk grows with the size of the memory: the richer the store, the more near-duplicates it returns.

## 6. A Thin or Empty Result Is Not Proof of Absence

1. Empty recall means "this phrasing missed", not "this never happened".
2. Before saying "I have no record of that": run more query variations, then check the knowledge base as a separate source.
3. Report the outcome honestly — "not found after N variations" is a different claim from "it does not exist". State which one you mean (see `verification-gate`, Claim Provenance).

## 7. Red Flags

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| Answering "that project" from plausible inference | Fabricates shared history the user will believe | Detect the gap, fetch from memory, then answer |
| Web-searching a question about the user's own past | The answer is not public; the search returns noise | Query long-term memory and the knowledge base |
| Describing a module's behavior from recall | Codebase memory goes stale between sessions | Open the file and read it |
| Web-searching an API of an already-installed dependency | The exact pinned version is on disk | Read the installed package, then its version-matched docs |
| Concluding "we never discussed it" after one failed query | Recall is lexical; one phrasing proves nothing | Run 3–5 variations, then check the knowledge base |
| Merging two similar hits into one confident answer | Swapped names, terms, and details are silent misinformation | Separate the branches; ask one question or answer per branch |
| Running deep research to answer "how's it going" | Burns time and budget on a non-gap | Answer directly; no fetch |

## 8. Critical Rules

1. NEVER answer from invention when you notice a gap — fetch or say plainly that you do not know.
2. ALWAYS classify the gap type before choosing a source; the wrong source wastes the turn and returns garbage.
3. NEVER treat the codebase as something to remember — read it.
4. NEVER merge similar-but-divergent recall hits; separate or ask one question.
5. MUST run multiple query variations before declaring anything absent from memory.
6. ALWAYS prefer the cheap source when uncertain whether the gap is real.

## 9. Related Skills

- `verification-gate` — how to state what you fetched: TRUSTED vs UNVERIFIED, and never hedging a verified fact.
- `live-research` — the protocol for outside-world gaps about libraries and APIs before coding.
- `systematic-debugging` — owns its own research step; this skill does not override it.
- `context-management` — the other half of context: window pressure, checkpoints, handoffs. Different job.
