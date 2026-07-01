---
name: verification-gate
description: Use when about to claim work is complete, fixed, or passing. Requires running verification commands, backup before destructive changes, doc freshness checks, stack-agnostic compilation checks, and visual checks for any UI/rendered output. Evidence before assertions, always.
---

# Verification Gate

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## Claim Provenance

Every claim you make carries a provenance level. State it — do not blur verified fact, cited source, and memory into one confident voice.

| Level | When to use | How to state it |
|-------|-------------|-----------------|
| TRUSTED | Verified this session (ran the command, read the file) or read directly from the repo | State as fact. No qualifier. |
| ATTRIBUTED | From an external source you consulted now | State with source + date |
| UNVERIFIED | Recall / training memory, not checked this session (may be 6–18 months stale) | Label it: "unverified —" |

**Anti-hedge (load-bearing).** What you verified is stated as fact, WITHOUT disclaimers. "should", "probably", "I think", "seems to" on a TRUSTED claim is a bug: it launders verified knowledge back into doubt and trains the reader to distrust everything you say. Hedge only what is genuinely UNVERIFIED.

**Research is obligatory only for MATERIAL claims** — those that affect architecture, a dependency or version choice, user-visible behavior, external compatibility, security, or a contested fact. For everything else, an explicit UNVERIFIED label is the honest move, not a browsing ritual.

**Reject mechanical citation rituals.** "Mentions a library → must go research it" is source laundering and disclaimer spam — it manufactures false confidence and buries the material claims that actually need checking. Materiality is the trigger, not pattern-matching. (Consistent with the 30-second rule in `using-subteams` §4.)

This "claim provenance" is distinct from the architecture-doc "provenance" check later in this file (§ Architecture-Doc Check), which is about ADR-traceability of design decisions. This section is about how you state any factual claim.

```
BAD:   "The build should pass now."                       (hedged — a verified fact dressed as a guess)
GOOD:  "Build passes — ran `npm run build`, exit 0."      (TRUSTED, stated as fact)
```

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you have not run the verification command in this message, you MUST NOT claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. BACKUP   → Create backup before any destructive change
2. IDENTIFY → What command proves this claim?
3. RUN      → Execute the FULL command (fresh, complete)
4. READ     → Full output, check exit code, count failures
5. VERIFY   → Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
6. DOCS     → Check documentation freshness
7. VISUAL   → If the output is visual (UI, page, image, diagram), view a
              screenshot and judge it looks right — not just that it renders
8. ONLY THEN → Make the claim

Skip any step = lying, not verifying
```

## When a Tool or Command Fails

A tool that errors, times out, returns empty, or returns stale data has told you NOTHING — it has not told you the answer is fine.

1. **State the failure plainly.** "The test command errored — exit 1, output below." Not silence, not a smoothed-over summary.
2. **Never fill the gap with a guess.** A failed check is not a passed check. Do not infer success from an absent result, and do not report a status you did not observe.
3. **Distinguish "tool failed" from "verified negative."** `grep` returning nothing because the pattern is genuinely absent is a real finding; `grep` erroring is you learning nothing. Say which one it is.
4. **If you genuinely cannot see it — say so** explicitly, and name what a working tool or a human would need to check. An unverifiable claim is reported as unverified, never as done.

## Backup Before Destructive Changes

BEFORE any operation that modifies or deletes existing code:

1. Verify the current branch is committed or stashed
2. For file deletions: confirm the file is tracked in version control
3. For refactors: ensure tests pass BEFORE starting
4. For database migrations: back up the database first

**NEVER assume you can undo.** Git reflog is a last resort, not a strategy.

## Stack-Agnostic Compilation Check

ALWAYS run the appropriate compilation/type check before claiming code compiles:

| Stack | Command | What It Proves |
|-------|---------|----------------|
| TypeScript | `npx tsc --noEmit` | Type safety, no undefined references |
| Python | `mypy .` or `pyright .` | Type correctness |
| Go | `go build ./...` | Compilation, import resolution |
| Rust | `cargo check` | Compilation without full build |
| Java | `mvn compile` or `gradle compileJava` | Compilation |
| C/C++ | `make` or `cmake --build .` | Compilation, linking |
| Dart/Flutter | `dart analyze` | Static analysis |
| Swift | `swift build` | Compilation |

**Linter passing does NOT mean code compiles.** These are separate checks. ALWAYS run both.

## Documentation Freshness Check

BEFORE marking work complete, verify documentation is current:

1. If public API changed: update API docs
2. If new module added: update module index or README
3. If behavior changed: update relevant guides or comments
4. If config options changed: update config documentation

**Stale docs are bugs.** Treat them as blockers.

## Architecture-Doc Check (structural / greenfield work only)

For greenfield projects and non-trivial structural changes (new module, new layer, dependency-direction change, new external integration), the architecture docs are load-bearing state — `architecture-guard` reads them as truth. Before claiming structural work is ready to implement or done, verify they are actually populated, with EVIDENCE, not on your word:

1. **Run** `scripts/check-arch-docs.sh <project-dir>` and read the exit code. Exit 0 = `docs/ARCHITECTURE.md` and `docs/CONVENTIONS.md` carry no stub markers; exit 1 = stub markers remain (the script prints which marker/file failed).
2. **Paste the actual output** (or the non-zero failure lines) as evidence. "The docs are filled in" without the script output is a claim, not verification — the whole point of this skill.
3. **Confirm provenance.** Spot-check that non-obvious architectural choices in `ARCHITECTURE.md` trace to an ADR (`## Decision Records`) or are marked `**TBD — unresolved**`. A doc that passes the marker scan but states an invented architecture is worse than a stub.
4. **Scope:** this check applies to structural/greenfield work ONLY — skip it for logic-only features, bug fixes, and in-module refactors. Do not run it on every task.

**A stub architecture doc that ships as "done" poisons every future session that reads it.** The mechanical check is cheap; the cost of authoritative-looking fiction is not.

## Visual Verification (when the output is visual)

Compilation and tests prove code RUNS — not that it LOOKS right. When the work produced a visual artifact — a UI page, component, landing page, rendered diagram, generated image, chart, or any human-facing layout — verification MUST include looking at it, whenever a way to see it exists.

1. **Render and look.** Capture a screenshot (`ui-testing` / Playwright / chrome-devtools for web UI; open the file for generated images, diagrams, PDFs). Actually view the result — never infer appearance from the code alone.
2. **Judge quality, not just "no crash".** Is the layout aligned, spaced, readable? Does it look intentional and polished, or broken / cramped / overflowing / off? Run the `design-qa` skill for a structured pass (hierarchy, consistency, contrast, spacing, responsiveness).
3. **Fix what looks wrong.** Misaligned, overflowing, low-contrast, clipped, or just ugly → fix it and re-screenshot. "It compiles" is not "it looks good."
4. **If you genuinely cannot see it** (headless env, no screenshot tooling, non-visual task) — say so explicitly: *"visual state NOT verified — needs a human/visual check."* Never silently claim a visual artifact is done without having looked at it.

This catches what `tsc` and unit tests never will: the thing renders without errors but looks broken.

## Common Verification Failures

| Claim | Requires | NOT Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Types correct | Type checker: 0 errors | "TypeScript compiles" without running tsc |
| No regressions | Full test suite: all pass | Running only new tests |
| Requirements met | Line-by-line checklist | Tests passing |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Arch docs populated (structural work) | `check-arch-docs.sh` exit 0 + output shown; choices trace to ADRs | "I filled them in", template still has stub markers |
| UI intact | Screenshot comparison: no visual regressions | tsc passes, unit tests pass |
| Visual artifact looks good | Screenshot viewed + judged: aligned, readable, polished | "compiles" / "no regressions" (regression-free can still look broken) |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit/push/PR without verification
- Trusting agent success reports
- Relying on partial verification
- Thinking "just this once"
- ANY wording implying success without having run verification

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence is not evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter is not compiler |
| "Agent said success" | Verify independently |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## Evidence Patterns

**Tests:**
```
CORRECT:  [Run test command] → [See: 34/34 pass] → "All tests pass"
WRONG:    "Should pass now" / "Looks correct"
```

**Build:**
```
CORRECT:  [Run build] → [See: exit 0] → "Build passes"
WRONG:    "Linter passed" (linter does not check compilation)
```

**Requirements:**
```
CORRECT:  Re-read plan → Create checklist → Verify each → Report gaps or completion
WRONG:    "Tests pass, phase complete"
```

## When to Apply

**ALWAYS before:**
- ANY variation of success/completion claims
- ANY expression of satisfaction
- ANY positive statement about work state
- Committing, PR creation, task completion
- Moving to next task
- Delegating to agents

## The Bottom Line

**No shortcuts for verification.**

Run the command. Read the output. Check the docs. THEN claim the result.

This is non-negotiable.
