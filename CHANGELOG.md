# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.38.2] - 2026-07-22

### Changed
- **Gemini hierarchy made explicit across the plugin (operator decision, 22.07.2026):** new "Gemini hierarchy" block in `using-subteams` — native Claude agents are ALWAYS the primary team for every role including frontend/design; Gemini lanes #17-20 are cross-model alternatives on explicit request only, never outranking, replacing, or running ahead of the native agent, their findings never overriding native findings (disagreements → cross-review §3.2 escalation). Same sentence added to `cross-review` §1.8. Pipelines must stay complete and self-sufficient on Claude agents alone (agy availability is not guaranteed).

### Fixed
- Roster rows #17-18 still listed the pre-1.38.0 tool set (`Read, Grep, Glob, Bash`) after the frontmatter trim — now `Read, Bash`, matching the agent files.

## [1.38.1] - 2026-07-22

### Changed
- **Priority clarification (operator decision, 22.07.2026):** the Claude pipeline is the PRIMARY frontend designer; `gemini-frontend` — like every Gemini lane — is an ALTERNATIVE dispatched only on explicit request, never a default. Rationale: agy availability is not guaranteed and the pipeline must be self-sufficient without it. Roster #20 reworded accordingly (docs-only release).

## [1.38.0] - 2026-07-21

### Added
- **Gemini direct-call layer `scripts/gemini/` (operator decision: no sonnet middleman).** Four executable scripts the orchestrator calls straight from Bash: `agy-run.sh` (generic runner: display-label mapping with `fast`/`pro` presets, timeout discipline — outer always above `--print-timeout`, soft-deny detection from stderr, per-run model log-verification with `[verified|DEGRADED→…]`, optional strict JSON mode with single-fence tolerance, `-o` file output so big results land on disk not in context; found live: agy drains stdin even in `agy models`, so the availability probe runs `</dev/null`); `review.sh` (third-model code review: diff materialization with bad-base-ref vs empty-diff discrimination → Pro-High call → findings JSON); `design-critic.sh` (visual critique of rendered images, context via file so quotes/`$` are inert); `frontend.sh` (competing HTML draft from a brief with structural validation `<!DOCTYPE html>…</html>`, 630 s default). All three role scripts verified live end-to-end (the review script immediately caught a real SSRF-class regex gap in a live diff).
- **New agent #20: `gemini-frontend`** — competing frontend draft generator, approved by the operator on 21.07.2026 after a live judge-panel duel (same brief → Claude pipeline vs Gemini one-shot). Thin harness over `frontend.sh`; delivers an UNEDITED alternative draft, explicitly marked not-yet-reviewed, routed through design-qa/brand check before use. Tools: Read, Write, Bash.

### Changed
- **Direct-call doctrine everywhere:** using-subteams model note + new doctrine block, cross-review §3.1, design-qa §6.5 — the default method for every Gemini lane is the script via Bash; agent files #17-20 are the opt-in isolation mode and, when spawned, also just run the script. Manual bash blocks in agent files remain as documented fallback.
- **Agent tools trimmed to necessary-and-sufficient:** #17-19 `Read, Grep, Glob, Bash` → `Read, Bash` (Grep/Glob were never used by the harness procedures); #20 ships as `Read, Write, Bash` (Write only to save the generated artifact).

## [1.37.0] - 2026-07-21

### Added
- **New agent #19: `gemini-design-critic`** — optional cross-model DESIGN lane: structured Gemini critique of RENDERED visuals (screenshots at breakpoints, image renders, PDF-preview captures, poster/cover art) with severity-graded findings across hierarchy / typography / spacing / color-contrast / artifacts / responsive integrity / taste. Complements `design-critic` (which reviews code and spec) by judging the pixels users actually see, from a non-Claude aesthetic distribution — taste disagreements between families are the signal. Same proven harness shape as `gemini-code-reviewer`: pinned "Gemini 3.1 Pro (High)" (env `GEMINI_DESIGN_CRITIC_MODEL`), single agy call with `read_file`-only mandate and all images in one call (cross-screen consistency), JSON validation with single-fence tolerance, mandatory model log-verification with DEGRADED marking, graceful `gemini-design-unavailable` + mandatory degradation relay. Aesthetic findings are explicitly framed as attributed judgment; artifact-class findings (clipping, overflow, contrast) as checkable defects.
- `design-qa` §6.5 upgraded from a single ad-hoc option to a two-tool lane: `gemini-design-critic` for structured QA on client-facing/public artifacts, `gemini-analyst` for quick one-question looks. Opt-in doctrine unchanged.

### Changed
- `using-subteams`: roster #19, model note now covers Gemini agents #17-19.
- `README.md`: roster table + claudemd-snippet agent list carry all three Gemini agents.

### Deferred by design
- A Gemini design GENERATOR (competing drafts in web-design-pipeline) is deliberately NOT an agent yet: through headless agy Gemini emits text (HTML/CSS/specs) only, and its generative design quality is unproven here. Next step is a live judge-panel experiment on a real design task; formalize only if it earns it.

## [1.36.0] - 2026-07-21

### Added
- **New agent #18: `gemini-code-reviewer`** — optional THIRD cross-review lane (Gemini via Antigravity CLI `agy`), additive to the Claude and GPT critic families, opt-in only: explicit "triple review" request or top-tier (public/irreversible/security) change at orchestrator discretion — never a silent default until quality is proven on real diffs. Harness: materialize the diff to /tmp → single `agy --model "Gemini 3.1 Pro (High)" -p` call (env override `CROSS_REVIEW_GEMINI_MODEL`, display-label only) with `read_file`-only mandate → JSON findings validated before trusting (zero-exit-but-empty/invalid output is reported loudly, never mislabeled as "no findings") → mandatory log-verification of the actual model. Verified live on a bug-seeded diff: Pro (High) caught float-cents money bug, `Math.random()` idempotency key, and `res.json()`-on-error crash in one pass (~29 s).
- **Mandatory degradation notification** across all Gemini lanes: `gemini-review-unavailable` / `gemini-unavailable` must reach the user-facing summary (merged-report line + orchestrator relay duty in `cross-review` §3.3/§6.4 and the using-subteams model note) — a missing lane must never read as "all models agreed". Repeated unavailability of the consumer-preview quota is a tell-the-operator signal, not something to absorb.
- **Design QA cross-model lane (optional):** `design-qa` §6.5 — `gemini-analyst` as an independent non-Claude visual pass on screenshots/rendered artifacts (opt-in, additive to design-critic, same degradation doctrine).

### Changed
- `cross-review`: §1.8 Gemini-lane triggers, §2 Gemini model policy (documented deviation from the no-hardcode rule: agy's settings default is Flash — right for the analyst, too shallow for review; agy has no per-role config), §3.1 optional fifth critic, §3.3 Gemini-Only Findings section, §6.4 fallback+notification, §9 agent row.
- `using-subteams`: roster #18, model note (Gemini agents #17-18, degraded lane always surfaced), Full Step 6 + Standard step 5 clarify the Gemini lane is opt-in and NOT part of the GPT-critics default.
- `gemini-analyst`: model log-verification recipe hardened against concurrent-run log interleaving (found live: a parallel session's agy run made bare `grep | tail -1` return another process's model line; now newest-by-mtime file + match the `Print mode: starting` line to your own flag).
- `README.md` agent roster caught up: both Gemini agents added to the table and the claudemd-snippet agent list (the 1.35.0 release had wired `gemini-analyst` into using-subteams only, leaving the README enumeration at 16 while the marketplace description advertised 17 — release-review finding).

### Considered and rejected
- Gemini as an additional **researcher** lane: headless `agy` has no web access (all non-`read_file` tools soft-denied), so it would answer from training data alone — a stale-knowledge opinion, not research. Second opinions on synthesized findings remain available ad-hoc via `gemini-analyst`; `live-research`/`researcher` stay Claude+web.

## [1.35.0] - 2026-07-21

### Added
- **New agent #17: `gemini-analyst`** — a sonnet harness that shells out to the Antigravity CLI (`agy`, Google Gemini) in headless print mode, mirroring the Codex-critic pattern (availability check → single structured invocation → graceful "gemini-unavailable" degradation, never blocking the pipeline). Its niche: multimodal media analysis Claude agents cannot do at all — video frames with verified temporal precision (exact-second answers on a test clip) and images — plus a Gemini cross-model second opinion. The agent prompt encodes the empirically verified 1.1.5 gotchas: `--model` accepts only display labels ("Gemini 3.1 Pro (High)"), slugs from `agy models` are silently ignored (log-verified model reporting is mandatory whenever a `--model` flag is passed); `--effort low|medium|high` works; headless soft-denies tools outside `permissions.allow` (only `read_file(*)` is allow-listed; stderr capture is read after every call); video is ingested frames-only, the audio track is not passed (independently re-verified on a speech clip); `--dangerously-skip-permissions` is forbidden. Roster row + model-note wiring in `using-subteams`. Reviewed by prompt-evaluator (FAIL → 7 findings fixed → PASS, live smoke tests).

### Fixed
- `marketplace.json` version drift: entry still said 1.34.4 while plugin.json shipped 1.34.6 — both now carry the release version.

## [1.34.6] - 2026-07-16

### Fixed
- **Mid-run Codex collapse could be silently mislabeled as findings.** The GPT critics keyed availability solely on the `codex exec` exit code. If Codex exited zero but wrote an empty or truncated output file (died mid-generation — network drop, auth expiry mid-call, model error after the process had already started), the agent `cat`-ed the empty file and presented it under `Status: findings-returned`, hiding the collapse. Both `gpt-code-reviewer` (two invocation blocks) and `gpt-devils-advocate` now validate the structured output after a zero exit: empty or non-JSON output downgrades to `Status: cross-review-unavailable` with reason "codex exited 0 but produced empty or invalid output (likely died mid-generation)". A mid-run failure is now reported loudly and never mislabeled. `cross-review` skill §6 documents the broadened availability contract. Degradation stays non-blocking (exit 0, Claude-only review continues) — unchanged.

## [1.34.5] - 2026-07-16

### Fixed
- **Cross-model reviewers (`gpt-code-reviewer`, `gpt-devils-advocate`) failed on every run after a Codex upgrade.** Codex 0.144.5 enforces OpenAI structured-outputs STRICT mode on `--output-schema`, which the shipped schemas violated on two counts: (1) every object needs `"additionalProperties": false`, and (2) `required` must enumerate **every** declared property (nullable fields use a `["type","null"]` union but must still be listed). The old schemas omitted both, so Codex returned HTTP 400 `invalid_json_schema` and the agents degraded to "cross-review-unavailable" on every invocation. Both the pretty-printed doc schema and the compact heredoc schema in each agent are corrected and re-verified against live Codex (rc=0, valid JSON out). Schema-conformance only — no change to review logic. The degradation contract (announce loudly, exit 0, Claude-only review continues) is unchanged and stays correct.

## [1.34.4] - 2026-07-15

### Changed
- **Preflight growth allowance +15 → +40** (operator calibration after the first live autonomous run): a modest legit edit to a large file flows, generated-monster growth still stops; `replace_all` positive deltas still always deny.
- **Preflight × cohesion doctrine reconciled explicitly** (hook header pt. 4 + clean-architecture cross-ref): no conflict, a hierarchy — interactive mode judges cohesion via review (hook silent), autonomous mode applies the hard fuse and routes "justification" through operator escalation; a self-written comment or ADR is not operator sign-off, and the hook must never be taught to accept one.
- **Risk-triggered plan sections wired through the project lifecycle** so they get filled and stay fresh instead of existing as an option: `brainstorming` captures User Stories / Data Design / Interface Contract at spec time (same triggers), `writing-plans` Self-Review checks presence-where-fired AND absence-where-not, `living-plan` Update refreshes the matching section when a closing task changed behavior/schema/API ("a stale story misleads the ui-tester that reads it as scenarios"). Anti-ceremony guards preserved and reinforced; prompt-evaluator PASS on all three checks incl. both smoke directions.

## [1.34.3] - 2026-07-15

### Fixed
- **Backlog F4 closed: `git commit` as literal text no longer trips the gate.** The top-level filter previously substring-matched the whole command, so `make build && echo "then git commit"` false-blocked when unreviewed code was staged. Now the command is split on `&&`/`;`/`|` and the match is anchored to a statement's command position — with tolerance for leading `VAR=value` env assignments (review caught the bare anchor letting `GIT_EDITOR=true git commit` slip the gate the 1.32/1.33 releases deliberately hardened). Bonus fix: the old echo-start exclusion also wrongly skipped `echo foo && git commit` (a REAL commit); the anchor catches it now. Known-low-realism remainders (documented, not chased): `\git` / `command git` / bare-subshell `(git commit)` skip; a quoted `| git commit` inside a string can still false-trigger — fails toward running the gate, never toward missing a commit.

## [1.34.2] - 2026-07-15

### Fixed
- **The doc-discipline Stop reminder was invisible in practice** — live multi-instance testing proved the hook fired correctly (changeset markers written, valid JSON emitted) but the CLI does not render Stop-hook `systemMessage` at all (the official hooks docs list only `additionalContext` for Stop). P8 rule 1's systemMessage-only delivery therefore silenced the reminder for everyone. **Superseded by explicit operator confirmation (15.07.2026, quoted in the hook):** delivery is now channel-configurable via `CLAUDE_SUBTEAMS_DOC_REMIND_CHANNEL=system|context|both` (default `both`, the 1.29-proven JSON shape). The model-visible `additionalContext` carries a mandatory anti-swallow header (P8 rule 3): repeat your pending answer/question verbatim first, relay the advisory in one line, start no work because of it. P1 per-instance scoping, cooldown, and once-per-changeset gating unchanged. Reviewed: APPROVE (quoting, fallback escaping vs hostile input, marker-gate integrity, header imperativeness all verified).

## [1.34.1] - 2026-07-15

### Changed
- **Review gate docs-class widened** (operator request): `.txt`, `.csv`, `.rst`, `.adoc` now skip the review gate alongside `.md` — prose/data text is not code. Deliberately still gated: `.html` (site code, operator decision), `.yaml`/`.json` (behavior-bearing configs), and — micro-review finding — `requirements*/constraints*.txt` (dependency manifests wearing a .txt extension stay gated; a blanket .txt skip would have opened a supply-chain-class bypass the surrounding comment itself warns about).

## [1.34.0] - 2026-07-15

Night batch, fully autonomous under an explicit operator grant: the last enforcement item from the 1.32 plan (P3.2 convention pre-flight) plus the operator's standing cross-model preference written into the pipeline. Dual-model review as first-class process: the diff was reviewed in parallel by a Claude code-reviewer and GPT (Codex, high effort, prompt-only path) — each found real defects the other missed; all fixed and re-verified with live hook runs before this commit.

### Added
- **`convention-preflight` hook (PreToolUse, Edit|Write|MultiEdit) — deny gate for growing large code files, autonomy-only.** Interactive mode: strict no-op (post-edit-check already owns the post-hoc advisory). Under `CLAUDE_SUBTEAMS_AUTONOMY`: denies growing a >400-line code file past a +15-line allowance (small bugfixes flow, meaningful growth stops), a Write that grows an existing large file, and a brand-new >400-line file materializing in one write (deliberate asymmetry vs the edit path — no incremental history behind it; documented in the header). Shrinking rewrites always pass. `replace_all` with a positive per-occurrence delta is treated as unbounded growth (GPT review caught the bypass: per-edit counting let a 20-occurrence replace_all slip under the net). Escape hatch `CLAUDE_SUBTEAMS_SKIP_PREFLIGHT=1`; fail-open on any parse/tool error. Explicit non-goals in the header: no import-direction analysis (stays with architecture-guard), no CONVENTIONS.md threshold override (a deny gate must not take its threshold from an untrusted project file).

### Changed
- **GPT critics are now the strong default, not an option** (operator standing preference, 15.07): using-subteams cross-model note + Standard step 5 + cross-review §1.7 — when Codex is available, `gpt-code-reviewer` runs alongside code-reviewer and `gpt-devils-advocate` alongside devils-advocate as equal-rank reviewers for any Standard-or-above review; unavailability degrades to Claude-only without blocking and never becomes a quiet permanent skip. Trivial-mechanical changes stay exempt (consistent with cross-review §1.6).

### Fixed
- Line counting in the new hook: `split("\n")|length` overcounted newline-terminated content by one (GPT finding — a normal 400-line file was denied; an asymmetric trailing-newline edit produced a phantom +1 delta, Claude finding). Both branches now count identically, trailing terminator excluded.
- Write branch originally gated absolute size, denying a 900→450-line shrinking rewrite (Claude finding) — now gates on growth for existing files.

## [1.33.0] - 2026-07-15

The loop release: the audit's "enforcement over prose" line meets the operator's loop-engineering direction. An opt-in autonomous loop over the living plan, a monkey-testing mode for the ui-tester, risk-triggered plan sections, and a repo-aware review gate. Implemented by developer + prompt-engineer subagents; gated by code-reviewer (2 medium found → fixed) and prompt-evaluator (1 blocker found → resolved); the review gate itself was E2E-verified live in this release cycle (real SubagentStart payload captured, marker keyed to the parent session).

### Added
- **`autonomous-loop` skill — in-session plan loop, strictly opt-in.** Walks the active IMPL-PLAN item by item: select `[ ]` → pipeline execution (review floor holds: any logic → code-reviewer; security/breaking → full critic set incl. GPT cross-review when Codex is up) → mechanical checkpoint (typecheck + tests + `check-plan.sh` + `autonomy-check.sh --checkpoint`, real output only) → green: mark `[x]`, next; red: one fix attempt, second red = blocker-checkpoint. Activation needs BOTH an explicit loop request in the current operator message AND a fresh autonomy run record — no self-activation, no stale grants, bare "continue/продолжай" is an explicit anti-trigger. Kill-switch: any operator message. Plan rewriting stays inside living-plan bounds (add/split free; acceptance criteria = REVISED + operator ack = loop stops). No Stop-hook nudge, by operator decision — continuation is behavioral. Two-strike fuse (vs interactive three) is deliberate: unattended runs earn a stricter fuse.
- **`ui-tester` monkey mode.** `mode: monkey` in the brief switches from scenario-based testing to chaotic traversal — random clicks, garbage/boundary input, double submits, back/forward, viewport hopping — via Playwright CLI **headless** (explicitly NOT agent-browser, NOT computer-use; one browser process, closed at timebox end — VPS constraint). Collects console errors, unhandled rejections, failed requests; 5xx/console/rejection = defect, 4xx on garbage input classified as validation-observed, not an issue. Reproducibility required (seed or ordered action log); 3-5 min timebox per route. Scenario mode now reads `## User Stories` from the active IMPL-PLAN when present.
- **Risk-triggered optional plan sections** (writing-plans + IMPL-PLAN template): `## User Stories` (user-facing features; doubles as the ui-tester's scenario source), `## Data Design` (schema changes), `## Interface Contract` (new/changed public API → docs/openapi.yaml). Explicitly NOT default ceremony — no trigger, no section; doubt about the trigger itself arms that one section, general uncertainty arms nothing.
- **Reviewer-name rule** (using-subteams §2, cross-review §3.1, autonomous-loop): in harnesses where a custom spawn name replaces `agent_type` in the hook payload (observed live in teammate mode), review agents must be spawned unnamed or with `code-reviewer` in the name, or the review gate cannot see the review. Verified live both ways in this cycle.

### Fixed
- **`pre-commit-gate` is now repo-aware.** The review gate and size signal previously evaluated the SESSION cwd's staging area; `cd X && git commit` and `git -C X commit` were judged against the wrong repo (post-1.32 finding). The hook now resolves the target repo from the command (git -C on the commit statement, else the last cd before it; quoted paths with spaces supported — review finding; `~`/`$HOME` expand; other substitutions fall back to cwd) and runs all staged checks with `git -C "$TARGET_DIR"`, CONVENTIONS.md lookup included.
- **`git -C <path> commit` previously bypassed the ENTIRE hook** — the old top-level filter only matched bare `git commit`, so compilation check, review gate, and size signal all silently skipped `-C` commits. Found while testing the repo-aware fix.
- Latent `LARGE_FILES` path bug: staged paths are repo-root-relative, but file reads assumed cwd == repo root; now joined against the resolved repo root.
- `executing-plans` autonomy failure table: the `reviewer-disagreement | END-OF-RUN only` row read as "skip reviews mid-run", contradicting the review floor (evaluator blocker). Clarified: task-level review always runs; what is deferred to run end is *resolving reviewer disagreements* as a blocking gate.

## [1.32.0] - 2026-07-14

Enforcement release: the external cross-model audit of 2026-07-12 (Claude 8/10 + GPT 5.5/10) concluded the plugin's core works but its critical rules live in prose the model obeys selectively — "the next quality jump comes from subtraction, telemetry, and enforcement." 1.32 moves three load-bearing rules into mechanics, fixes two operator-reported Stop-hook failure modes, replaces the hard line-count doctrine with cohesion, and vendors the ponytail YAGNI ladder. Plan with all operator decisions: docs/plans/2026-07-13-subteams-1.32-research.md. Implemented by developer + prompt-engineer subagents; reviewed by code-reviewer (bash) and prompt-evaluator (prompts); every finding fixed or explicitly accepted below.

### Added
- **`using-subteams` §0 Load-Bearing Rules.** Five one-line rules (classify scope first; any logic change → code-reviewer; a claim without evidence is not done; never silently substitute the agreed approach; when unsure, ask) placed above everything else, with an explicit precedence clause: when any detailed rule seems to conflict, the load-bearing rule wins. Response to the audit finding "the model retains slogans, not 24 rules" — the slogans are now curated instead of emergent.
- **Review gate (P3.1): `git commit` with staged code now requires a code-reviewer run this session.** `subagent-rails` (SubagentStart) writes a session marker when `agent_type` contains "code-reviewer" (field name verified against the official hooks docs 2026-07-14; `.subagent_type` kept as defensive fallback); `pre-commit-gate` denies a commit with staged non-doc files when the marker is absent. Escape hatch `CLAUDE_SUBTEAMS_SKIP_REVIEW_GATE=1`; fails open when session_id is unreadable (can't prove absence without identity). **Known coarseness, by design:** the gate proves "a reviewer ran this session," not "this exact diff passed review" — the honest floor for a hook, review quality stays on the orchestrator.
- **Per-instance change scoping (P1): the doc reminder no longer blames other instances' files.** `post-edit-check` records every Edit/Write (repo-relative, dedup-on-write) into `$XDG_CACHE_HOME/claude-subteams/session-edits/<session_id>`; `session-end-reminder` intersects `git status` with that registry. Empty registry + `CLAUDE_SUBTEAMS_MULTI_INSTANCE=1` → silence (never blame a peer); without the flag → 1.31 behavior. Accepted gap: Bash-driven edits (git mv, sed) bypass the registry and degrade toward silence, documented in both hooks.
- **`lazy-implementation` skill — vendored ponytail core (MIT, DietrichGebert/ponytail, adapted 2026-07-14).** The 7-rung YAGNI ladder, rules, output contract, intensities, and "When NOT to be lazy" carried over near-verbatim; test guidance rewritten to defer to the pipeline (test-engineer owns depth — laziness never trims a required gate). The ladder is also embedded in compact form in `agents/developer.md` (climb before you write; security/trust-boundary/data-loss handling never trimmed). Re-sync with upstream quarterly.

### Changed
- **Stop-hook hygiene (P8): `session-end-reminder` is now operator-only.** All advisories go out as `systemMessage` alone — `additionalContext` removed from every path, so the hook can no longer overwrite the model's final answer or provoke unrequested work (both failure modes operator-observed). All message strings rewritten from model-directed phrasing to human-addressed ("ask the agent for it" instead of "don't act now").
- **Cohesion doctrine (P9): size is a review signal, not a violation — everywhere.** Primary principle: a file/class/function is one semantic unit; split along semantic seams, never by a line counter. Default review thresholds 300 lines/file, 80/function (project CONVENTIONS.md wins); past threshold = ask "still one responsibility?" — justify in one line or split by meaning; a true god-file *changes for unrelated reasons* (axis-of-change SRP test), long-but-cohesive is clean. Applied consistently to `using-subteams` Rule 14, `clean-architecture`, `conventions-enforcer` (the CONVENTIONS.md generator — highest-risk lag caught by prompt-evaluator), `refactoring`, `code-review` §4.1, `agents/developer.md`, `agents/architecture-guard.md`, `agents/improvement-agent.md`, `templates/CONVENTIONS.md`, `templates/project-init/CLAUDE.md`. Hooks (`post-edit-check`, `pre-commit-gate`) go silent when the project has its own CONVENTIONS.md; without one they flag at 400 (deliberately coarser than the 300 review line — last-resort net, commented in both).
- **The 3-specialist-skill cap is removed** (operator decision 13.07). `using-subteams` §5 rule 2 is now a relevance rule: load what genuinely changes your actions, no numeric ceiling; prioritization guidance retained, same-ground skills resolve to the more specific one.

### Fixed
- `pre-commit-gate` ERRORS concatenation could render two gate messages on one line (missing separator) — review finding, fixed with `${ERRORS:+\n}`.
- `session-edits` registry grew one line per repeated edit of the same file — now dedup-on-write.
## [1.31.1] - 2026-07-07

### Fixed
- **`coord.sh claim`/`release` silently operated on only the LAST path of a multi-path call.** The positional-arg loop overwrote a single `path` variable, so `claim --id X a b c` claimed only `c` — while the session-start protocol line and the multi-instance SKILL both nudge agents to pass lists. Observed in production (claudebot, 2 live instances): a day of batch claims each protected one file, with no error. Both commands now collect paths into an array. `claim` is **all-or-nothing across the batch**: any path held by a live peer → exit 3, *nothing* is claimed, and every conflict is named on stderr (printed from under the flock, against the post-reap ledger). `release` drops every listed path owned by the caller, skipping peers' claims. Each batch is a single `_jq_write` (one atomic rename), so a partially-applied batch can never appear on disk. Exit-code contract (0/2/3/4/5) preserved; rc=1 (internal jq/ledger failure, nothing written) now documented in the usage header.
- **Path validation:** empty paths and paths with embedded newlines are rejected with rc=2 (`_valid_paths`) — the old single-path code rejected empty loudly, and the new line-based plist build would have split a newline path into two ledger keys. A file literally named `--all` still can't be released by name (flag wins) — pathological, documented in the header.
- **`marketplace.json` version de-staled** (sat at 1.30.0 through the 1.31.0 release; both files now 1.31.1).

Docs updated to the new contract: usage header, multi-instance SKILL §3.1/§3.3 (`<path> [<path>...]`, all-or-nothing note), session-start protocol line. Verified by a 30-case isolated suite (multi-claim, idempotent re-claim, batch conflict incl. position-0 (jq `index()==0` truthiness), foreign-claim preservation on mixed release, `--all`, arg errors, quote-in-path JSON safety, empty/newline rejection) — all green; reviewed by code-reviewer (pass, suggestions applied).

## [1.31.0] - 2026-07-06

Planning-depth work on `brainstorming` (unchanged since 1.18.0): the stack becomes a consciously *compared* decision, and rejected options now survive in the durable ADR. Scope was cut from 5 proposed changes to 2 by a four-critic plan review (Claude + Codex/GPT reviewers and devil's-advocates) applying the 1.28.0 audit verdict "subtract, don't add" — a spec template, a mechanical spec gate, and an interview-rule de-dup were all rejected with reasons. Authored by prompt-engineer, validated by prompt-evaluator against artifact predicates, reviewed by code-reviewer. See [ADR-010](docs/adr/010-stack-as-compared-decision-and-adr-alternatives.md).

### Added
- **`brainstorming`: the stack is now a compared decision, not a gathered constraint.** A **Stack Decision** step (checklist item 4 + a dedicated section) fires on greenfield OR a live stack decision — where "live" weighs task fit, team familiarity, ops cost, and ecosystem maturity, explicitly NOT the bypassable "does the current stack technically work." It emits an observable Stack Decision block (2-3 candidates, the chosen stack, one-line reason each rejected candidate lost); when the stack is genuinely fixed, the skip must be stated, not silent. The chosen stack is recorded as an ADR via `adr-tracker` **decoupled from** the greenfield/structural Architecture Capture gate — so a stack pick in a non-greenfield project has somewhere to land, while a logic-only feature that adds one library gets an ADR and is NOT dragged into `ARCHITECTURE.md`/`CONVENTIONS.md` population. Honesty invariant: the stack ADR is `proposed` until the user approves, `accepted` only after.
- **`Alternatives considered` section in the ADR contract.** Rejected options now live in the durable ADR that `architecture-guard` reads as truth, not only in the ephemeral `decision-context` journal block. Added to all four copies of the format — `templates/adr-template.md`, the adr-tracker format block, the Example ADR, and the Creation Checklist — plus a Red Flag for a missing / `N/A` Alternatives, and a reconciliation line naming the ADR section canonical and the decision-context field its lightweight companion.

### Changed
- **Architecture Capture step 1 honesty invariant harmonized.** The generic arch-choice ADR-creation bullet said status `accepted` "the instant a choice is settled" — during the interview, before design approval, contradicting both the new Stack Decision lifecycle and step 2's own "each accepted ADR" (which runs post-approval). Now `proposed` at capture, `accepted` only on approval, for ALL architectural choices — a latent inconsistency, not just a stack one — with an anti-duplicate reminder to reuse an existing Stack Decision ADR, and the ADR field list updated to include Alternatives.
- **`brainstorming` Spec Self-Review** gained two checks: non-goals stated explicitly, and (if a stack decision was made) the spec links to its ADR. Genuine unknowns route to an "Open Questions" prose heading — the arch-doc-only `**TBD — unresolved**` marker is deliberately kept out of spec context.

## [1.30.0] - 2026-07-06

### Changed
- **`session-end-reminder`: fire-once granularity is now per *changeset*, not per session.** The session marker stores the bare list of undocumented (non-doc) changed files at the last fire, written atomically; the reminder re-fires only when the current set contains a file the stored set lacks AND the marker is older than the cooldown (default 45 min, `CLAUDE_SUBTEAMS_DOC_REMIND_COOLDOWN_MIN`). A shrinking set never re-fires; short sessions behave exactly like 1.29.0; day-long sessions no longer go blind after the first advisory. NOTES-only / not-a-git fires write an empty set and don't self-repeat (accepted; can delay the first real code advisory by up to one cooldown window — still strictly better than 1.29.0's whole-session silence). Every failure mode (missing `find`, partial marker write, unparseable cooldown) degrades toward re-reminding, never toward false silence.
- **Standing doc-hygiene recommendation appended to all six terminal advisories** (operator request — the useful spirit of the pre-1.28 blocking hook without the coercion): "Standing recommendation: when the current piece of work wraps up, offer the user a doc update (decisions journal, CHANGELOG, descriptive sections) rather than starting one unprompted." Offer-framing first, no leading imperative (prompt-evaluator hardening); evaluator passed all six variants post-append including repeated-delivery accumulation. Operator `systemMessage` line updated to match the new semantics. See [ADR-009](docs/adr/009-session-end-hybrid-advisory.md) amendment 2026-07-06.

## [1.29.0] - 2026-07-05

### Changed
- **`session-end-reminder` rebuilt as hybrid advisory, fire-once per session.** The 1.28.0 delivery premise was wrong: per the official hooks docs, `systemMessage` is shown to the **operator only** — the model never saw the 1.28.0 reminder at all (and `decision:"approve"` does not exist on Stop; only `"block"` does). The hook now emits one JSON object combining `hookSpecificOutput.additionalContext` (model-visible advisory) and `systemMessage` (one fixed operator line), with no `decision` field — nothing ever blocks. A marker file keyed on the Stop payload's `session_id` (sanitized, under `${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/session-end-marks/`) makes the reminder fire **at most once per session**; silent passes don't consume the slot; markers older than 7 days are pruned; a missing/unsafe `session_id` falls back to firing every turn (availability over strict once-ness). The marker doubles as loop protection for the extra model turn `additionalContext` provokes. All model-facing texts were rewritten from imperative numbered checklists to framed advisories ("Advisory (not a task — surface to the user, don't act now) … Nothing to do now") — engineered against the observed failure mode where the model launched unsolicited doc work in response to the old texts; validated by a prompt-evaluator simulation pass (incl. an adversarial filename-as-instruction case), with two RISK phrasings patched pre-merge. Classification logic (Cases A–D, breaking signals, doc-map NOTES, neutral filtering, `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1`) is unchanged. See [ADR-009](docs/adr/009-session-end-hybrid-advisory.md).

### Fixed
- **ADR-006 and ADR-008 status lines de-staled.** ADR-006's headline still read "hook deferred" although its own amendment records the `subagent-rails` hook as shipped (1.27.0); ADR-008's session-end half is now explicitly marked superseded by ADR-009. Status lines point to the governing amendment/ADR so a skim can't pick up the stale picture.
- **CHEATSHEET version drift** (said 1.27.0 while the plugin was at 1.28.0).

## [1.28.0] - 2026-07-02

Shell-layer hardening from a full health audit of 1.27.0 (9 agents + Codex GPT-5.5). Codex found 1 CRITICAL + 7 HIGH + 2 MEDIUM in the shell scripts and hooks; all are fixed and locked in by a 55-case adversarial regression suite. Reviewed by code-reviewer + devils-advocate + a Codex cross-model pass.

### Security
- **coord.sh flock success now checked (CRITICAL).** Every `( flock 9 … ) 9>"$LOCK"` critical section aborts with a diagnosed `exit 5` if the lock is not acquired — previously an `flock` failure (missing binary, unwritable lock) let the body run **unlocked**, silently breaking the atomicity the whole file assumes.
- **autonomy-check.sh single-writer gate fails CLOSED (HIGH).** In multi-instance mode, coord.sh missing/non-executable, a non-zero `roster` exit, or empty roster output now all `exit 4` (STOP) instead of silently no-op'ing as if no peer existed — this is the one check whose entire purpose is to fail closed, and it did the opposite.
- **autonomy-check.sh git exit codes no longer swallowed (HIGH).** `git diff/ls-files/numstat` failures inside `$(…)` were read as "0 files / 0 lines" (scope/cap checks passing on a git error). Each is now exit-code-checked and fails closed on a real git failure; an empty-but-successful result still proceeds.
- **coord.sh deregister path-traversal closed (HIGH).** `cmd_deregister` now `_valid_id`-validates `--id` before using it as an inbox path, matching every sibling command.
- **coord.sh _reap_locked word-splitting fixed (HIGH).** jq keys iterated via `while IFS= read -r` (was unquoted `for`), so a hand-edited instances.json key with whitespace/glob chars can't skip a reap.
- **coord.sh roster read made atomic (HIGH).** Reap + length + roster print now happen in one `flock` section — no stale-roster window for the single-writer check to trust.
- **coord.sh notify-due lock aligned (HIGH).** notify-due now takes the per-inbox lock that send/recv use (was the shared `$LOCK`), so it actually excludes a concurrent send. No new deadlock (single lock per critical section, verified).
- **check-plan.sh oversized plan is a FAILURE (HIGH).** A >1 MB IMPL-PLAN sets `FAILED=1` (non-zero exit) instead of printing SKIPPED and passing green, honoring the "Exit 0 = every plan valid" contract.
- **autonomy-gate Bash record-guard reverted to blanket-deny (MEDIUM, regression fix).** The 1.27.0 read/write classifier was shown by cross-model review to be trivially bypassable (`cat /dev/null; mv payload <record>` latched read-only on the leading `cat`, then wrote via the second command; `sort -o`/`uniq` wrote without a `>`), and strictly worse than the prior deny-all. Any Bash command referencing the run record is now denied outright — read it with the Read tool. Still best-effort against indirection that never names the record (documented residual, ADR-007).
- **autonomy-gate pre-scan DoS guard (MEDIUM).** The per-tool-call `grep` over active plan files now stat-guards with `MAX_RECORD_BYTES`; an `OVERSIZED_SEEN` flag prevents the size-skip from opening a new fail-open (an unscanned oversized file no longer takes the "no record → allow" shortcut — it hands off to the fail-closed script).

### Changed
- **`session-end-reminder` downgraded from blocking to a non-blocking, model-visible reminder.** The hook fires on `Stop` — which is **per assistant turn, not end-of-session** (the filename is a misnomer, kept for wiring stability). It used `exit 2` to *block* the turn until docs were written, coercing the model mid-work every turn. It now emits a single `{"decision":"approve","systemMessage":"…"}` JSON on stdout and `exit 0`: never blocks, and (unlike a bare `printf`+exit 0, which on Stop is transcript-only) the reminder actually reaches the model. All the doc-classification logic (Case A–D, breaking signals, doc-map freshness, escape hatch) is preserved; only enforcement→reminder and the delivery channel changed. The dead `/tmp` counter/HEAD-hash blocking machinery is removed. See [ADR-008](docs/adr/008-session-end-reminder-nonblocking.md).
- **`pre-commit-gate` no longer sources nvm on every Bash call.** nvm is sourced only inside the `git commit` → tsconfig branch, so `ls`/`cat`/`grep`/etc. early-exit without the ~190–220 ms nvm tax (measured); the compilation check is otherwise unchanged.

### Notes
- Deferred (documented, not blocking): AC3 could halt a run on a transient `.git/index.lock` — accepted (fail-closed asymmetry favors a re-invocation over an off-cap run); hooks.json's unquoted `${CLAUDE_PLUGIN_ROOT}` command path is accepted-residual (install paths under `~/.claude/plugins/` have no spaces — contingent on install location). Pre-existing, orthogonal items filed to BACKLOG: single-writer check doesn't require self in roster; unchecked sequential `_jq_write` in coord.sh; unlocked `recv --count` peek.

## [1.27.0] - 2026-07-02

### Added
- **Task Contract — the plan-of-record in two weights** (Tier 2 of the planning/autonomy/honesty modernization, spec `docs/specs/2026-07-01-planning-autonomy-honesty-design.md`). `living-plan` now routes by a **light contract** (scope / acceptance criteria / non-goals — for risk-triggered or multi-session single-feature work) vs the **full package→criterion→status matrix** (multi-package / TZ-with-acceptance). The old "≥2 packages only" threshold is gone; a **risk-trigger mandates writing the artifact, not a deeper pipeline** (tiebreak explicit, 4 worked examples). **Write-once acceptance criteria:** originals are immutable after approval; changes append as `REVISED: <what> — <why> — "<operator-ack quote>"` lines (ack required on scope/acceptance change), validated (format only) by `check-plan.sh`. `subagent-driven-dev` now keeps the matrix in lockstep (previously it did not, so the plan died when that executor was chosen). Reviewers review the diff against the **written** criteria via the brief's `Rails:` field.
- **Risk-trigger governance** (`using-subteams` §6): eight risk-triggers (six objective — schema/data-invariant, public API, new dependency/stack, destructive migration, security boundary, autonomous execution; two self-assessed — ambiguous intent, large blast radius) select **artifact depth**, while file-count is demoted to an effort estimate. Standard-pipeline risk work gets a light contract without escalating to Full-pipeline gates.
- **Scoped autonomy — `## Autonomy Mode`** in `executing-plans`, enforced by a new **`autonomy-gate` PreToolUse hook** + **`scripts/autonomy-check.sh`**. Opt-in per grant via `CLAUDE_SUBTEAMS_AUTONOMY` (inert when unset); a per-grant run record (in the active plan, between `<!-- autonomy-run:begin/end -->` markers) carries scope globs, base commit, session, expiry, and total-run caps (`CLAUDE_SUBTEAMS_AUTONOMY_MAX_FILES/LINES`). The gate structurally blocks, before the edit lands, out-of-scope or cap-exceeding writes (canonical-path matched against `../`/relative/symlink spellings) and edits to the run record itself; milestones become non-blocking evidence checkpoints. See [ADR-007](docs/adr/007-autonomy-enforcement-architecture.md).
  - **Honest scope (not oversold):** bounded autonomy **contains an agent that drifts off its granted scope** — the common failure mode — and is **NOT a sandbox against an agent that deliberately rewrites its own grant via shell** (a Bash-equipped agent can write any file; the gate's Bash record-write block is best-effort pattern-matching, not a guarantee). Grant autonomy accordingly. The adversary-resistant path (harness-env grant fingerprint) is deferred to Tier 3.
- **`subagent-rails` SubagentStart hook** — injects static rails pointer + honesty reminder into every spawned subagent (delivery empirically confirmed on CLI 2.1.197; static plugin text only, never repo content). See [ADR-006](docs/adr/006-subagent-rails-hook-deferred.md) amendment.
- **`session-start` resume** — lists up to 3 active plans (name, age, next non-DONE criterion, BLOCKED count) + a `check-plan.sh` verdict, recommend-not-command; repo-controlled plan text is truncated + control-char/backtick-stripped + framed as untrusted (prompt-injection hygiene).

### Changed
- `check-plan.sh` gains a conditional `REVISED:`-line format check (zero-REVISED plans still pass) and a 1 MB size guard; de-forked to a single awk pass per plan.
- `living-plan` / `writing-plans` / `orchestrator-briefing` / `IMPL-PLAN.md` template updated for the two-weight model and the run-record schema (one key per line).

### Security
- Hardening from a two-round, five-agent adversarial review (code-reviewer, architecture-guard, devils-advocate, security-auditor, Codex): fixed dead-on-arrival hook wiring (missing event arg); killed a run-record field-forgery vector (multi-key line splitter removed); canonical-path matching closes record-edit bypass via `../`/relative/symlink; `autonomy-gate` resolves repo-root so it cannot fail open from a subdirectory; deny-JSON built via `jq` (control-char safe); `AUTONOMY_BASE_COMMIT` charset-validated + `--end-of-options`; 1 MB DoS guards on all plan/record parsers. 142 adversarial tests green.

## [1.26.0] - 2026-07-01

### Added
- **Honesty invariant — tool-failure honesty, claim provenance, anti-hedge, materiality — across the whole plugin** (Tier 1 of the planning/autonomy/honesty modernization, spec `docs/specs/2026-07-01-planning-autonomy-honesty-design.md`). See [ADR-004](docs/adr/004-honesty-invariant-placement.md).
  - **Authoritative detail in `verification-gate`:** new `## Claim Provenance` section (TRUSTED / ATTRIBUTED / UNVERIFIED levels; anti-hedge as a load-bearing rule — verified facts stated as fact, WITHOUT disclaimers; research obligatory only for MATERIAL claims; mechanical citation rituals explicitly rejected) and `## When a Tool or Command Fails` (state the failure plainly; a failed check is not a passed check; "tool failed" ≠ "verified negative"). Namespaced "claim provenance" vs the pre-existing arch-doc provenance check.
  - **Compact 4-bullet block in every agent** (`agents/*.md`, byte-identical, right after `## Who You Are`) — the agent prompt is the only delivery channel guaranteed to reach delegated work. The materiality bullet (verify material claims if tools allow, else flag for the orchestrator) was added in review: without it a subagent could label a material claim UNVERIFIED and feel compliant (devils-advocate finding).
  - **`using-subteams` §4.1 pointer + Red Flags row** ("I'll smooth over the failed/empty tool result…"). `researcher` additionally maps its confidence scale to claim provenance (different dimensions, both required).
- **Rails delivery into subagents via the briefing channel.** New mandatory `Rails:` field in the orchestrator-briefing Complete Brief Template (conventions/architecture docs + active plan the subagent must read before acting) and a `Rails read:` acknowledgment line in the subagent output contract — a short quote of the applied constraint plus the diff file:line. Honestly documented as an attention prime + spot-check anchor (two cross-referable anchors), NOT a checkable guarantee — posture-tier by design. Output-contract enumerations in `subagent-prompt-design` and `agent-engineering` synced (review caught them contradicting the new mandatory field). See [ADR-006](docs/adr/006-subagent-rails-hook-deferred.md).

### Changed
- **Scoped autonomy re-sequenced to Tier 2** after a three-critic plan defense (devils-advocate + architecture-guard + Codex cross-model): every safety claim of the Tier-1 draft (non-blocking caps, self-classified failure classes, env "gate" nothing executable reads, no post-compaction re-hydration) was posture, not structure — shipping it would be confidence theater. Tier 2 builds autonomy ON the canonical Task Contract with machine-checkable enforcement (diff-based scope gate, blocking caps + total-run budget, fail-closed grant record, kill-switch). See [ADR-005](docs/adr/005-autonomy-resequenced-to-tier2.md). No autonomy semantics ship in 1.26.0; `executing-plans` and hooks are untouched.
- marketplace.json description corrected: 16 specialized sub-team agents (was stale "12").

## [1.25.0] - 2026-06-22

### Added
- **Autonomous mailbox delivery — peer messages reach promptless agents.** The 1.24.0 notifier fired only on `UserPromptSubmit` (interactive only); an agent running autonomously for hours never fires it. `coord-notify` now also runs on `PostToolUse` (autonomous agents call tools constantly), **throttled to one notice per newly-arrived message** via `coord.sh notify-due` (a per-instance `notify/<id>.last` timestamp marker — robust across `recv` clears). See [ADR-003](docs/adr/003-autonomous-mailbox-delivery.md).
  - **Polling discipline is the backbone** (skill §3.7): the hook is an assist; the guarantee is the orchestrator running `recv`/`roster` at coordination checkpoints (before claim, after a work unit, before the commit-lock) and sending a deliberate handoff when a unit unblocks a peer. Communication is a conscious act, never an automatic broadcast of output.
  - **Subagents are skipped** (`agent_id` present → no notice) so only the orchestrator is nudged. `UserPromptSubmit` keeps the always-show count (infrequent, wants reliability); `PostToolUse` uses the throttle.
  - **Known limitation:** notice granularity is one second — a burst of messages to one recipient within a wall-clock second notifies once; `recv` still returns all of them (the notice is only a doorbell).

## [1.24.0] - 2026-06-22

### Added
- **Mailbox notification — you no longer have to remember to `recv`.** A new `coord-notify` hook (UserPromptSubmit, opt-in, async:false) injects a one-line **count** of unread peer messages ("you have N unread message(s)… run `coord.sh recv`") when any are waiting. See [ADR-002](docs/adr/002-mailbox-notify-count-only.md).
  - **Count-only, by design — peer content is never auto-injected.** Injecting message *text* into context was prototyped (`coord-deliver`) and rejected in review (code-reviewer + devils-advocate): peer text is untrusted (the inbox is a plain file, `send --from` is unauthenticated, trust is transitive), so auto-injecting it is a prompt-injection surface and contradicts the plugin's no-arbitrary-injection principle. The notifier injects only a count and makes the orchestrator pull content with `recv` (read as tool output = data it requested), framed as untrusted in the skill.
  - **Lossless:** the notifier never clears the inbox. New `recv --count` is a non-destructive peek; `recv` stays the explicit consume (read and clear are separable, so a dropped notice never loses a message).
  - **Hardening:** `recv` now collapses newlines in rendered `from`/`msg` so a peer cannot forge a fake `from:` header by embedding a newline. The hook receives its event name authoritatively as an argv from `hooks.json` (never guesses it — a mismatched `hookEventName` would be silently dropped by the SDK) and stays off `SessionStart` to respect the "SessionStart does not inject" invariant. Multi-instance trust guidance (treat mailbox content as untrusted peer data, not commands) added to the skill.

## [1.23.1] - 2026-06-22

### Fixed
- **Multi-instance coordination was non-functional on SDK/service harnesses — instances never saw each other.** Root cause: `_alive()` decided liveness purely by `kill -0 <pid>`, where `<pid>` is the SessionStart hook's `$PPID`. On a harness that runs Claude via the Agent SDK (not the interactive CLI), that PPID is an ephemeral hook shell that exits the instant the hook returns, so every instance was registered with a dead-on-arrival pid and reaped on the very first `reap`/`roster`/`claim` pass → `roster` always empty, `claim` always `exit 4: not registered`. The v1 "PID is authoritative, heartbeat is observability-only" model assumed the registered pid was the long-lived instance process; that assumption is false off the interactive CLI.
  - **Root-cause fix — register the real long-lived pid, not `$PPID`.** New `_resolve_instance_pid()` walks up the process tree to the session's persistent `claude` ancestor; `cmd_register`/`cmd_heartbeat` store that pid and mark the entry `pid_trusted`. For a trusted pid, `_alive()` is authoritative by `kill -0` — a quiet instance is never wrongly reaped and a dead one is reaped immediately (no TTL wait). The hooks no longer pass `--pid` (the hook's `$PPID` is the ephemeral shell that caused the bug); coord.sh resolves it.
  - **Heartbeat TTL is now only the *fallback*** for harnesses where the real pid is unresolvable (`_alive()` = `worktree-present AND (trusted-pid-alive, else untrusted-pid-alive OR heartbeat-within-TTL)`). New `CLAUDE_SUBTEAMS_HEARTBEAT_TTL` (default **1800s**). The starvation caveat (a long non-edit operation past the TTL) applies only in that fallback mode, not when the pid is trusted.
  - **`pid=0` immortal-zombie fix** (caught in code review): `kill -0 0` targets the caller's process group and always succeeds, so a sanitized `pid=0` entry was never reaped. `_alive()` now guards `pid > 0` before any `kill -0`, falling through to the heartbeat check.
  - **`cmd_heartbeat` is now self-healing (upsert):** an existing entry gets its heartbeat bumped; a *missing* entry is recreated (re-registered, re-resolving the trusted pid). This lets an instance that was reaped or deregistered come back on its next prompt/edit instead of vanishing for the session. `--id` is validated on the heartbeat path too. (A late async heartbeat just after SessionEnd can recreate a phantom entry; it holds no claims and is reaped once its real pid dies — bounded, documented in-code.)
  - **Deregistration moved from `Stop` to `SessionEnd`** (`hooks/coord-stop` → `hooks/coord-session-end`). `Stop` fires at the end of *every assistant turn*, so the old wiring released all of an instance's claims and deregistered it after every turn — claims could not survive across turns. `SessionEnd` fires once at real session end; if a harness never emits it (or on crash), a trusted-pid instance is still reaped immediately on process death, and an untrusted one via TTL.

## [1.23.0] - 2026-06-17

### Added
- **`multi-instance` skill + `scripts/coord.sh` — opt-in coordination for several Claude Code instances on one machine/one repo** (Idea 3 of the 3-idea modernization, spec `docs/specs/2026-06-17-multiinstance-coordination.md`). Portable and deliberately **NOT** coupled to Claude Code's native agent-teams (so it survives onto other harnesses); file-based (flock + `jq` JSON + per-instance inbox), zero new runtime deps beyond `jq`. **Scope deliberately reduced** after a plan-defense review (agent-architect + devils-advocate): this v1 is registry + advisory file claims + a global commit-lock + a fire-and-forget mailbox + heartbeat. Deferred by design: shared task ledger, hooks-as-quality-gates, SQLite backend, fencing tokens, and any PreToolUse "enforcement" hook (claims are honest advisory coordination, not OS-enforced locks).
  - **`scripts/coord.sh`** — subcommands `init/register/deregister/heartbeat/roster/reap/claim/release/claims/send/recv/commit-lock`. Liveness is authoritative by **PID** (`kill -0`) + worktree existence on this single host — a PID-alive instance is never reaped on a stale heartbeat (heartbeat is recorded for observability only; PID reuse is an accepted rare gap). Claim is an **atomic claim-or-reject under flock** and requires a registered live instance (an unregistered claimant fails loudly, never silently void). Orphan claims (holder no longer live) are pruned on reap; a corrupt/unparseable ledger **aborts** the prune rather than wiping all claims. `recv` tolerates a malformed inbox line (skips it, keeps the rest). `--id`/`--to` are validated (no path traversal); `--pid` must be numeric. Coord dir keyed by `git --git-common-dir` (with a `cksum` fallback if `md5sum` is absent) so all worktrees of one repo share one registry.
  - **Opt-in gate `CLAUDE_SUBTEAMS_MULTI_INSTANCE`** — `coord.sh` and every new hook branch no-op (early `exit 0`) when unset, so single-instance sessions are unaffected. (The one non-zero cost is the existing hooks' extra gated `jq`/heartbeat line; no new always-on PreToolUse hook was added.)
  - **Hook lifecycle wiring:** SessionStart registers + reaps + injects a `[subteams:multi-instance]` awareness line (you are instance `<id>`, the live roster, the claim-before-edit protocol, the `GIT_OPTIONAL_LOCKS=0` tip); UserPromptSubmit + PostToolUse refresh heartbeat; a **separate** Stop hook (`hooks/coord-stop`) deregisters + releases claims independently of the doc-enforcement Stop hook (so it is not skipped when that one `exit 2`s). Crash/OOM cleanup falls to PID-based reap.
  - **2–3 instance cap** on ≤4 GB hosts surfaced in the skill (lived OOM lesson). Wired references in `using-subteams` (§10) and `orchestrator-briefing` (pre-claim files before dispatching a subagent).

## [1.22.0] - 2026-06-17

### Added
- **`living-plan` skill — a single multi-level plan-of-record for multi-package / contracted work** (Idea 2 of the 3-idea modernization, spec `docs/specs/2026-06-17-living-plan-ledger.md`). Solves the "real plan scattered across estimate + BACKLOG + specs, acceptance-readiness invisible at a glance" problem. The artifact is a matrix that rolls up: `package → TZ section → acceptance criterion → status (DONE/WIP/TODO/BLOCKED) → blocker/owner`, in `docs/plans/active/IMPL-PLAN-<slug>.md`.
  - **Scope-gated:** mandatory ONLY for ≥2 packages OR a TZ with acceptance clauses; single-feature work keeps using the brief `writing-plans` plan (no bureaucracy on small tasks).
  - **`templates/IMPL-PLAN.md`** — starting template with the `> STATUS: TEMPLATE — not yet populated` sentinel and the status-token convention.
  - **`scripts/check-plan.sh`** — mechanical validator: sentinel removed, Rollup table present, every checklist item carries a recognized **trailing** status marker (`— DONE/WIP/TODO/BLOCKED`, or `TBD` for an unresolved criterion). Exit 0 when valid OR when no plan-of-record exists (it is optional — absence is never a failure); exit 1 when a present plan is malformed. Evidence, not self-attestation. Hardened in pre-publish review: status matched as a trailing marker (not anywhere in prose), `TBD` recognized so a faithfully-authored unresolved criterion validates, and a final line without a trailing newline is checked.
  - **In-context authorship discipline** (same as architecture-capture): acceptance criteria are authored from the real estimate/TZ, never fabricated — unknowns marked `**TBD — unresolved**`.
  - Wired into `writing-plans` (author the plan-of-record for qualifying work) and `executing-plans` (flip criterion status + recompute Rollup as tasks close). README skills roster updated.

## [1.21.0] - 2026-06-17

### Changed
- **Doc-freshness gate now covers the doc map and tightens the feature-class tracker rule** (Idea 1 of the 3-idea modernization, spec `docs/specs/2026-06-17-living-plan-ledger.md` / plan `docs/plans/active/2026-06-17-three-idea-modernization.md`). Closes a confirmed gap: a commit of "code + a new spec" passed the freshness checks silently because any `.md` touch counted as "docs remembered", so the doc map quietly lagged every new spec.
  - **`hooks/session-end-reminder`**: detects when a changeset adds a **new** doc under `docs/specs/` or `docs/adr/` (added / untracked / renamed-in, via `--untracked-files=all` so a fully-untracked parent dir doesn't hide it; path parsed from column 4 so spaces don't truncate it) while the project's **doc map** is left untouched, and emits a **non-blocking** reminder. The doc map is auto-detected from common names (`docs/INDEX.md`, `INDEX.md`, `docs/SUMMARY.md`, `mkdocs.yml`) or set via `CLAUDE_SUBTEAMS_DOC_MAP`; **when no doc map exists the hook stays silent** (never nags a project to invent one — the plugin's own repo has no INDEX.md and must not be flagged). The new-doc scan and the map-updated check read from one shared all-untracked listing for consistency. Emitted once before the case logic, so it fires regardless of classification and never changes the exit code. Existing Case A–D behavior (breaking-signal block, 2-attempt loop guard) is untouched.
  - **`skills/doc-quality-gate/SKILL.md`**: new section 2.5 "Cross-cutting: doc-map freshness" — a new tracked doc (spec/ADR) requires a doc-map entry regardless of class, explicitly reconciled with Class 1 ("none" governs the code, an added doc still owes a map entry), and a no-doc-map project is exempt. Class 2 (Feature add) now asks for CHANGELOG on user-visible/release-relevant features **and** a BACKLOG status update when the work was tracked (was "BACKLOG *or* CHANGELOG"; not over-mandated to "always"). Added Quick-Reference note, two Red Flags, Critical Rule 6.
  - Deliberately a reminder, not a block: scoped to *new* spec/ADR files and only when a doc map exists, to avoid false positives on doc-light, spec-editing, or map-less projects.

## [1.20.0] - 2026-06-15

### Changed
- **Cross-review reasoning effort now delegates to Codex's own config instead of the plugin parsing it.** Reverses the `awk`-based config detection shipped in 1.19.0. The effort flag is passed **only** when `CROSS_REVIEW_EFFORT` is set; otherwise nothing is passed and Codex resolves effort from its own config natively (`model_reasoning_effort`, profile-scoped keys, BOM — Codex parses its own TOML correctly). This is now genuinely symmetric to the `MODEL_FLAG` / `CROSS_REVIEW_MODEL` idiom: `[ -n "${CROSS_REVIEW_EFFORT:-}" ] && EFFORT_FLAG=(-c model_reasoning_effort="$CROSS_REVIEW_EFFORT")`. Applied at all 5 invocation sites (`gpt-code-reviewer` ×2, `gpt-devils-advocate`, `cross-review` skill `/rescue` + generic); policy text, "Why this matters", maintenance note, Critical Rules 1/2/7, and both output-contract Notes lines updated.
- **Why the reversal:** a full cross-model review of 1.19.0 (Claude + GPT-5.5 critics, the dimension this very change governs) converged on the `awk` heuristic being a leaky abstraction — it reimplemented a fragment of Codex's TOML/profile resolution in shell, producing real defects: a UTF-8 BOM or a `[profile.*]`-scoped key could silently mis-detect and either suppress or wrongly inject the `high` fallback, and the heuristic was copy-pasted across 5 sites. Letting Codex own value resolution removes that entire defect class. **Behavior change:** there is no longer a plugin-side `high` floor — if neither `CROSS_REVIEW_EFFORT` nor a Codex config effort is set, Codex runs at its own default. To guarantee deep reviews, set `model_reasoning_effort = "high"` (or higher) in `~/.codex/config.toml` (Critical Rule 2). For users with effort already configured (e.g. `xhigh`), the critics now inherit it exactly as Codex resolves it.

## [1.19.0] - 2026-06-15

### Changed
- **Cross-review reasoning effort is now config-driven with a `high` fallback** (was hard-forced to `high`). Precedence at every Codex invocation site: `CROSS_REVIEW_EFFORT` env var → a **top-level** `model_reasoning_effort` in `~/.codex/config.toml` (`$CODEX_HOME` honored) → `high` fallback. This makes effort symmetric to how model selection already works (`MODEL_FLAG`): the critics inherit a higher effort (e.g. `xhigh`) straight from the user's Codex config instead of being capped at `high`, while still guaranteeing at least `high` when neither the env var nor the config specify one — so cross-review never silently degrades to Codex's shallow bare default. Applied identically to all 5 invocation sites: `gpt-code-reviewer` (prompt + `review --base` modes), `gpt-devils-advocate`, and the `cross-review` skill's `/rescue` + generic escape-hatch blocks. Policy text, Critical Rules 1/2/7, the maintenance note, and both agents' output-contract Notes lines updated to match.
  - **Detection is a presence check, not a full TOML parse** (an `awk` scan that stops at the first `[section]` header). Known limitation, documented in the skill: an effort key scoped under a `[profile.*]`/`[model_providers.*]` section — or a config saved with a UTF-8 BOM — is not detected and triggers the `high` fallback. Set `CROSS_REVIEW_EFFORT` explicitly if you rely on a profile-scoped effort. Reviewed by Claude `code-reviewer` + cross-model `gpt-code-reviewer` (which both flagged the original section-blind `grep`; narrowed to top-level `awk` in response). The empty-array-under-`set -u` exposure is pre-existing and identical to the established `MODEL_FLAG` idiom, so left consistent rather than diverged.

## [1.18.0] - 2026-06-11

### Added
- **Architecture capture → projection → mechanical gate.** Closes the gap where architectural decisions made during `brainstorming` never landed in `docs/ARCHITECTURE.md`/`docs/CONVENTIONS.md` — those files stayed template stubs while structural work proceeded against them. New flow: each accepted architectural decision is captured **during the interview** as an ADR (`adr-tracker`) + a `decision-context` block; then the orchestrator, **in-context** (it holds the dialogue — never a fresh-context subagent), projects those records into `ARCHITECTURE.md` + `CONVENTIONS.md` with ADR provenance links. Unresolved items are marked `**TBD — unresolved**`, never invented. NO new agent — the fix is capture semantics + a mechanical gate, not labor. (Two adversaries, Claude `devils-advocate` + cross-model `gpt-devils-advocate`, converged: a fresh-context author reconstructing decisions from a lossy brief produces "authoritative-looking fiction", and these docs are load-bearing state `architecture-guard` reads as truth — so a wrong doc poisons the validator.)
- **`scripts/check-arch-docs.sh`** — mechanical evidence script: scans `docs/ARCHITECTURE.md` + `docs/CONVENTIONS.md` for stub markers (sentinel `> STATUS: TEMPLATE — not yet populated`, `<PLACEHOLDER>`, `<STACK>`, etc.), exit 0 = populated, exit 1 = stub markers remain (prints which). Provides evidence, not self-attestation. (Authored under Task A.)
- **using-subteams Full Pipeline Step 4.5 — Architecture-Capture Gate (Critical Rule 24).** Greenfield and non-trivial structural work does NOT enter IMPLEMENT until `check-arch-docs.sh` passes AND every non-obvious architectural choice traces to an ADR. **Scope is strict** — greenfield + new module / new layer / dependency-direction change / new external integration ONLY; NOT every Full-pipeline task, NOT logic-only features, bug fixes, or in-module refactors. Invoked inside the pipeline, never as a global commit hook — by design it does not fire on small changes (bureaucracy was the explicit failure mode the adversaries flagged). New `user-prompt-check` hook branch emits a `[subteams:scope]` advisory on greenfield/structural signals.

### Changed
- **brainstorming** — new "Architecture Capture" section + step-7 branch: capture-at-decision (ADR + decision-context block during the interview), then orchestrator in-context projection into the arch docs with provenance links; stub markers removed only once a section holds a real decision or `**TBD — unresolved**`. Capture at the moment of decision, never reconstruct later.
- **project-scaffold** — Step 4 handoff now states explicitly that scaffolded `ARCHITECTURE.md`/`CONVENTIONS.md` are stubs that MUST be populated through the brainstorming capture flow before structural implementation; references `check-arch-docs.sh` and Rule 24.
- **verification-gate** — new "Architecture-Doc Check" section + Common-Failures row: for structural/greenfield work, run `check-arch-docs.sh` and paste the output as evidence (not on your word); spot-check ADR provenance.
- **using-subteams** — `Full + Architecture` pipeline row extended (greenfield + gate); skill version 1.7.0 → 1.8.0.

## [1.17.1] - 2026-06-11

### Fixed
- **Canonical update flow.** `scripts/update.sh`, the README/CHEATSHEET "Update" sections, and the `llms-install` already-installed branch documented only `claude plugin marketplace update articortex` — which refreshes the marketplace catalog but does NOT move the version-pinned installed plugin, so users stayed on the old version. The canonical Claude Code update is **two steps**: `claude plugin marketplace update articortex` then `claude plugin update claude-subteams@articortex` (interactive: `/plugin marketplace update articortex` → `/plugin update claude-subteams@articortex` → `/reload-plugins`). `update.sh` now runs both. No plugin behavior changed — docs/tooling only.

## [1.17.0] - 2026-06-11

### Added
- **Two agentic-quality specialists.** `prompt-engineer` (opus) authors and optimizes prompts, system prompts, and tool/skill instructions — context-first, eval-driven, hands off to `prompt-evaluator`. `agent-architect` (opus) designs subagents and multi-agent systems — boundaries, orchestration topology, tool scoping, contracts — applying the `agent-engineering` and `subagent-prompt-design` methodology. Until now those skills existed as *knowledge* but there was no specialist *persona* to dispatch for authoring/design (only `prompt-evaluator`, which tests). Agent count 14 → 16.
- **using-subteams §6.5 — Agentic & Prompt Work (mandatory wiring).** When the task is building/editing agents, system prompts, skills, tool definitions, MCP servers, or multi-agent systems, the pipeline now mandates the agentic skills (`agent-engineering` + `subagent-prompt-design` + `prompt-evaluation`, treated as core not specialist — they do not count against the 3-skill cap) and the Author → Evaluate → Iterate loop (agent-architect/prompt-engineer produce, prompt-evaluator proves). Skipping the agentic specialists on agentic work is now a process failure (Critical Rule 22). New Scope-Detection row + `user-prompt-check` hook branch surface agentic work automatically.
- **using-subteams §6.6 — Change Verification gate (every pipeline above Lightweight).** Before declaring done, confirm with EVIDENCE (not memory) that required gates ran: reviews happened and findings were addressed, tsc/lint/tests are actually green, docs updated per `doc-quality-gate`. Skipped gates must be stated explicitly, never presented as passed. Critical Rule 23.
- **project-scaffold — Retrofit mode (§8).** The skill now has two modes: *Init* (empty dir, unchanged) and *Retrofit* (existing project with source code but missing/weak docs). Retrofit is additive and non-destructive: audits which standard docs are present/stub/substantive, infers real values from the repo (never fabricates), fills only gaps, and never overwrites populated docs without asking. Step 2 now routes empty→Init, source-present→Retrofit instead of aborting. New `session-start` hook signal flags a source project with < 2/5 core docs.

### Changed
- **Review is required for every logic change, calibrated by weight.** Lightweight pipeline is now reserved for *zero-logic* mechanical edits (rename, typo, import, formatting); the moment a change touches behavior it escalates to Standard. Standard review is calibrated: **code-reviewer always**, plus **devils-advocate for non-trivial logic** (multi-file, branching, contract/shared-state, or any uncertainty). A single isolated one-liner gets a reviewer but not an adversarial challenger; substantial logic gets both. Closes the gap where small logic changes shipped unreviewed without imposing two opus agents on every typo-adjacent fix. Critical Rule 21; Red Flags, executing-plans gate, and README roster note updated (devils-advocate is no longer "Full pipeline only").
- **agent-engineering / subagent-prompt-design** cross-reference the new specialist agents (rulebook → execution handoff).
- **Roster sync** across README, INSTALL, llms-install, templates/claudemd-snippet, docs/CHEATSHEET (16 agents), and using-subteams §2.
- using-subteams skill version 1.5.0 → 1.7.0.

## [1.16.1] - 2026-06-01

### Added
- **llms-install.md: optional repair appendix.** A non-mandatory section so an AI agent handed the install protocol can also REPAIR a legacy/broken install — detect a corrupted marketplace list or a stale pre-v1.14 `bn-skn` local registration, remove it (CLI branch when `/plugins` works; manual JSON-edit branch with backups when it's dead), then install cleanly. Mirrors `docs/CHEATSHEET.md` but inline in the agent protocol, with explicit "touch only the bn-skn entries, never blanket-delete" safety.

## [1.16.0] - 2026-06-01

### Added
- **verification-gate: visual verification.** Compilation and tests prove code RUNS, not that it LOOKS right. Added a "Visual Verification" section: when work produces a visual artifact (UI page, component, landing page, rendered diagram, generated image, chart), verification MUST include viewing a screenshot and JUDGING quality — aligned / readable / polished, not merely regression-free — and fixing what looks wrong before claiming done. Wired into the Gate Function (new step 7), the Common Failures table, and the skill description. If the artifact genuinely cannot be seen (headless env, no screenshot tooling), that must be stated explicitly, never silently claimed complete. Capture via `ui-testing` / Playwright / chrome-devtools; structured quality pass via `design-qa`.

## [1.15.0] - 2026-06-01

### Added
- **using-subteams: Specialist Skill Catalog** — Section 5 now lists all 53 skills grouped by category (planning, quality, architecture, agents/authoring, domain/stack, docs, research, process). Most specialist skills are invoked by domain relevance (the 1% Rule), not via cross-references — so the catalog is the discovery surface that tells the orchestrator the full arsenal exists, not just the skills referenced from elsewhere. (Fixes the gap where ~15 domain/specialist skills were findable only by description, never named in the methodology.)

### Changed
- **project-scaffold wired into the spec → plan → implement process.** Now creates `docs/specs/` (where `brainstorming` writes design specs), and Step 4 explicitly hands off the spec/plan flow for a new project: `brainstorming` (spec → `docs/specs/`) → `writing-plans` (plan → `docs/plans/active/`) → `using-subteams` (implement). Previously the scaffold built the doc skeleton but didn't connect it to spec-writing — a fresh project landed with no clear "now write the spec" next step.

## [1.14.2] - 2026-06-01

### Fixed
- **using-subteams agent roster** — the two GPT critics (`gpt-code-reviewer`, `gpt-devils-advocate`) were wired into the pipeline (Full Pipeline Step 6 cross-model layer, Standard review) but were MISSING from the Section 2 "Default Agents Quick Reference" table. Added them as #13-14 (model/tools/when-to-spawn/output) plus a cross-model note clarifying they are optional and Codex-gated. The roster now matches reality (14 agents) and the README agents table — orchestrators reading the methodology see the full team.

## [1.14.1] - 2026-06-01

### Changed
- **Docs freshness pass.** Removed the stale hardcoded "12 specialized agents" count from the activation snippet (source `templates/claudemd-snippet.md` + its copies in README / INSTALL / llms-install, and the `using-subteams` description) — now reads "specialized sub-team agents", and the agent enumeration is extended to all 14 (added `gpt-code-reviewer`, `gpt-devils-advocate`). Actualized `docs/plans/active/2026-05-02-full-audit-overhaul.md` (counts 9/46 → 14/53; C1-C3 marked resolved by the v1.14.0 marketplace migration; C4/I1-I6/A1-A6 remain open backlog). Historical snapshots (`docs/DONE.md`, CHANGELOG history) intentionally left intact.

## [1.14.0] - 2026-06-01

### Changed
- **Distribution migrated to a proper GitHub marketplace.** Added `.claude-plugin/marketplace.json` (marketplace `articortex`, plugin `claude-subteams`, source `./`). Install is now the official flow — `/plugin marketplace add bn-skn/claude-subteams` then `/plugin install claude-subteams@articortex` — instead of a bash script that hand-edited Claude Code's global JSON state. This kills the fragile installer whose fabricated `source: "local"` registration became invalid in current Claude Code and corrupted the marketplace list. `install.sh` / `update.sh` / `uninstall.sh` are now thin CLI wrappers (~660 → ~210 lines total) that never touch `known_marketplaces.json` / `installed_plugins.json` / `settings.json`. Private repo works with the user's git/gh credentials (`gh auth setup-git` or `GITHUB_TOKEN`); the repo stays private — no public listing required.
- **llms-install / llms-uninstall / INSTALL / README** rewritten to the marketplace flow: layout-agnostic verification via `claude plugin list` (no hardcoded install paths), an upgrade note to remove the legacy `bn-skn` local clone, and the activation snippet embedded directly in the installer.
- **README cross-review entry** corrected — runs the full critic set by default (2 Claude + 2 GPT when Codex is available), not the old "1 GPT call / deep mode" split (that was removed in v1.12.1).

## [1.13.0] - 2026-06-01

### Changed
- **cross-review — native default model.** GPT critics no longer hardcode `gpt-5.5`. By default they pass NO `-m` flag, so Codex uses whatever model the Codex CLI is configured to use (`~/.codex/config.toml`) — upgrade the model natively in Codex and the critics inherit it with zero plugin edits. `CROSS_REVIEW_MODEL` optionally pins a specific model. Reasoning effort still defaults to `high` (Codex's own default is "none", which yields shallow reviews).

### Added
- **cross-review — run any agent through GPT (opt-in).** Beyond the two standing GPT critics, any specialist role (security-auditor, test-engineer, architecture-guard, design-critic, …) can be cross-checked on Codex/GPT via the same generic invocation pattern, on explicit request.
- **using-subteams — cross-model review wired into the pipeline.** Full-pipeline Step 6 now also dispatches `gpt-code-reviewer` + `gpt-devils-advocate` alongside the Claude reviewers when Codex is available (4 critics: 2 Claude + 2 GPT); falls back to Claude-only when Codex is down. Standard-pipeline review can optionally add the GPT reviewer. Never blocks the pipeline.

## [1.12.1] - 2026-06-01

### Changed
- **cross-review** — removed the quota-saving "default 1 GPT call / deep mode" split. `/cross-review` now dispatches the FULL critic set by default — both Claude critics (`code-reviewer` + `devils-advocate`) AND both GPT critics (`gpt-code-reviewer` + `gpt-devils-advocate`) — for complete cross-model coverage. Quota guidance reworded from a rationing constraint to awareness-only: run all critics whenever cross-review fires; pause Codex only if the human reports interactive ChatGPT being throttled (a reaction to a real signal, not a pre-emptive cap). Dropped the one-attempt-per-`/rescue`-session cap (no-auto-retry-on-failure remains, for reliability not rationing).

## [1.12.0] - 2026-06-01

### Added
- **cross-model review** — a second critic on a DIFFERENT model (OpenAI Codex / GPT-5.5) to break Claude's model-monoculture blind spots.
  - **gpt-code-reviewer** + **gpt-devils-advocate** agents — shell out to `codex exec` (read-only sandbox) for cross-model code review and architectural challenge. Paired with the Claude critics but with deliberately ORTHOGONAL prompts (concurrency / numeric / platform / spec-drift bugs; abstraction / contract / failure-model challenges) so the second model adds coverage instead of echoing Claude. Prompts are open-ended ("report anything material," not a closed checklist) with an `other_findings` channel for independent discoveries.
  - **cross-review skill** — `/cross-review` (Claude + GPT critics in parallel, merged by a deterministic escalation rule + an intersection heuristic with severity normalization) and `/rescue` (Codex diagnoses a stuck bug, read-only, human implements). Default mode = ONE GPT call to preserve ChatGPT Plus quota; deep mode = two, reserved for security-critical / breaking / new-service reviews.
  - **Model/effort policy:** strongest model at high reasoning effort (`gpt-5.5` + `model_reasoning_effort=high`), configurable via `CROSS_REVIEW_MODEL` / `CROSS_REVIEW_EFFORT` env vars — a single override point for both agents. This is deliberate: Codex defaults to NO reasoning effort, which yields shallow quick-scan reviews.
  - Graceful and safe: availability-checked before every call, never blocks the main pipeline when Codex is down, one attempt per call (shared quota), read-only sandbox always. Verified working from the dev environment (Codex CLI 0.135.0, gpt-5.5 at high effort).

## [1.11.0] - 2026-06-01

### Added
- **llms-install.md** — AI-readable installation protocol. A user hands the file to a coding agent ("@llms-install.md install this plugin"); the agent runs pre-flight capability/dependency checks, executes the installer (curl one-liner or clone path), verifies the JSON state, and reports. Designed for honesty over a happy path: declares required harness capabilities (shell / outbound network / process-substitution) up front, treats a `<()` syntax error as "use the clone path" rather than an install failure, gates on already-installed state (fresh-install vs re-run), reports "files installed — functionally unverified" instead of overclaiming (functional confirmation is the post-reload smoke test), and surfaces installer `WARNING:` lines verbatim.
- **llms-uninstall.md** — companion uninstall protocol: confirm installed → run uninstall.sh → verify removal across all three state files + the plugin directory → report.

### Changed
- **README** — added an "Install via an AI agent" subsection pointing to llms-install.md.

## [1.10.0] - 2026-06-01

### Added
- **doc-quality-gate skill** — model-side change classifier (cosmetic / feature / architectural / breaking) with per-class documentation requirements and doc-agent dispatch rules. Maps the hook's file signals to a class, then defines what docs each class needs. Delegates decision-block format and field discipline to `decision-context` (no duplication). Includes an honest scope note: the hook reminds via file signals, it does not verify documentation content — real breaking-change verification is the doc-agent audit plus judgment.
- **session-end-reminder hook — breaking-signal escalation.** The Stop hook now detects two reliable, asymmetric file signals — deletions (`git status D`) and schema/migration files (`migrations/`, `.sql`, `.prisma`, `schema.`) — and escalates its enforcement message to the full breaking-change checklist (CHANGELOG + descriptive rewrite + decision block + migration guide + doc-agent audit). Deliberately NARROW: routine additive signals (dependency manifests, new routes, `.proto`, `plugin.json`) do NOT trigger escalation — they flow through the standard reminder — to avoid false-positive fatigue that would push users to disable the hook entirely. Escalation also fires in the code+docs case when `CHANGELOG.md` is missing. Escape hatch (`CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1`) and the 2-attempt cap are unchanged.

### Changed
- **doc-agent** — added a third mode: breaking-change audit. Verifies that a breaking/architectural change has all required artifacts present and current: migration guide (if integrations break), API/contract docs, CHANGELOG entry, rewritten (not appended) descriptive section, and a decision-context block with non-empty Alternatives and Risks.

## [1.9.0] - 2026-06-01

### Added
- **live-research skill** — keeps the orchestrator and agents from coding against stale training-data knowledge of fast-moving APIs. Two command surfaces (`/research <question>`, `/whatsnew <library> [N months]`) plus a source-priority ladder (Context7 → Firecrawl → WebSearch → Serper) with graceful degradation. Architecture: the ORCHESTRATOR (main window, which holds MCP tools) fetches Context7/web docs and injects them into the researcher's brief as a `[Live Docs]` block — the dispatched researcher agent synthesizes them (it cannot call MCP tools directly, by tool-allowlist design). Portable: never hardcodes a Context7 MCP prefix; degrades to web sources when Context7 is absent.

### Changed
- **researcher agent** — Process step 3 now consumes Context7 docs injected via its brief (orchestrator-fetched) before generic web search, instead of attempting MCP calls it cannot make.
- **systematic-debugging** — added a category-gated live-research trigger: failures crossing a library/SDK/external-API boundary run live-research at Phase 1 (verify the API model is current before forming more hypotheses); internal-logic bugs (null, type, control flow, race) skip it and proceed straight to architecture questioning. Prevents wasting an opus research pass on bugs that were never API-knowledge issues.

## [1.8.0] - 2026-06-01

### Added
- **project-scaffold skill** — interactive wizard that bootstraps a brand-new project's documentation/config skeleton from one command. Gathers project parameters (name, goal, stack, frameworks, persistence, external APIs, build/test/lint/run/dev/install commands, repo URL, license) and assembles `CLAUDE.md`, `README.md`, `.gitignore`, `docs/SYSTEM.md`, plus `docs/plans/{active,completed}/` and `docs/adr/` seeds — reusing the existing `templates/*` for CONVENTIONS/ARCHITECTURE/BACKLOG/CHANGELOG/ADR. Safety: `ls -A` empty-directory check with a benign-file allowlist (`.git`, `.gitignore`, `LICENSE`, `README.md`, `.github`, `.DS_Store`) that never clobbers existing files, and a hard abort on real source/config (`package.json`, `pyproject.toml`, `go.mod`, `src/`, source files). Complements — does not overlap — the `scaffolding` skill: project-scaffold bootstraps a whole new project once; `scaffolding` adds components repeatedly. First of the v1.8 line, shipped incrementally.
- **templates/project-init/** — new bootstrap templates: two-layer `SYSTEM.md` (living system description + append-only decisions journal in the `decision-context` block format), a full project `CLAUDE.md`, a `README.md`, and a stack-agnostic `dot-gitignore` covering Node/TypeScript, Python, Go, OS, and editor artifacts.

### Changed
- **scaffolding** — "Project docs" Quick Reference row now points to the `project-scaffold` skill (single source of truth for initial project docs); added a "use project-scaffold first" note to When-to-Use to prevent trigger collision.
- **templates/ARCHITECTURE.md** — fixed the Related ADRs link from `docs/adrs/001-title.md` (plural, nonexistent) to `docs/adr/000-adr-template.md`, matching the directory the scaffold creates.

## [1.7.1] - 2026-05-21

### Fixed
- **install.sh**: marketplace description created by the install script said "9 specialized sub-team agents" — stale since v1.3.0 (developer) and v1.5.0 (ui-tester, improvement-agent). Now reads "12 specialized sub-team agents", matching reality. Cosmetic — does not affect install behavior, only the description text written to the user's local `marketplace.json`.

## [1.7.0] - 2026-05-20

### Added
- **session-end-reminder hook — now enforcing.** Smart Stop hook that detects unstaged code changes in the working tree and blocks `Stop` (exit 2) when non-doc files changed without any `*.md` updates. Behavior:
  - No changes / only docs / lock files → silent pass.
  - Code + docs both changed → soft reminder to confirm Decision-context block.
  - Code without doc updates → block with explicit instructions referencing the `decision-context` skill.
  - Counter resets on each new commit (HEAD change). After 2 enforcement attempts in the same HEAD state, allows stop with audit warning (prevents infinite loops if model cannot comply).
  - Not a git repo → soft checklist only.
- **CLAUDE_SUBTEAMS_SKIP_DOC_CHECK env var** — escape hatch to disable doc-enforcement for scratch / experimental work, CI contexts, or legitimate skip cases. Documented in `README.md` under "Configuration".
- **decision-context skill — new "End-of-Work Cycle" section.** Explains the start-of-work / during / end-of-work cycle for cases when no commit is happening (research, planning, debugging). Documents the Stop hook backstop and escape hatch. Adds two new Red Flags: stale descriptive docs, repeated Stop hook blocks.
- **decision-context skill — checklist for descriptive docs.** Step 4 of Workflow now mandates updating the descriptive part of the docs (top of `SYSTEM.md` or equivalent) by overwriting when affected, not just appending to the journal. "Stale descriptive docs are worse than missing ones."

### Changed
- **README.md** — Stop hook row in the Hooks table now describes enforcement behavior. New "Configuration" section documents `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK` and the full Stop-hook decision tree (no changes / docs only / code + docs / code only / not a repo / escape hatch active). Lists neutral files that never trigger enforcement.

## [1.6.0] - 2026-05-20

### Added
- **decision-context skill** — mandatory "decision context" block for every non-trivial change documented in `SYSTEM.md`, `CHANGELOG.md`, session journals, or postmortems. Five fixed labels: Decision / Why / Alternatives / Risks / Linked. Lightweight everyday companion to `adr-tracker` (which remains reserved for project-defining choices). Includes good/bad examples, field discipline, workflow, and red flags. Future-self insurance against cargo-cult and lost context six months later.
- Skill count: 48 → 49.

### Changed
- **git-workflow** — clarified commit-body rule. Was: "Body explains WHY, not WHAT". Now: for non-trivial commits the body MUST mirror the decision-context block from the project's decisions journal (cross-link to `decision-context` skill). Cosmetic / patch-bump commits still get a one-line body.
- **plugin.json** — bumped version `1.4.2` → `1.6.0` (was out of sync with CHANGELOG which already documented 1.5.0; resyncing in this release).

## [1.5.0] - 2026-05-11

### Added
- **ui-tester agent** (sonnet) — browser-based UI/E2E testing via Playwright CLI (not MCP). Takes screenshots, clicks buttons, fills forms, evaluates visual results. Works locally and generates CI-ready `.spec.ts` test files. Two modes: ad-hoc quick checks and standard test suite generation. Write access restricted to test files and config only — never touches source code.
- **improvement-agent** (opus) — proactive codebase analyst. Examines 7 dimensions: code health, dependency health, test coverage gaps, architecture drift, performance signals, log/error patterns, developer experience. Returns prioritized proposals (P0-P3) with file:line references. Read-only — never writes code. Explicit Bash constraints: forbidden commands documented.
- **ui-testing skill** — dispatch protocol for ui-tester agent with 3 testing levels (quick check, standard, full E2E). Includes CI integration template for GitHub Actions, token budget guidelines, and brief template.
- **codebase-improvement skill** — dispatch protocol for improvement-agent with 3 analysis modes (quick scan, standard, deep audit). Includes integration patterns and developer agent chain.
- Agent count: 10 → 12. Skill count: 46 → 48.

### Changed
- **executing-plans** — added UI/E2E testing and codebase analysis to Model Selection Guide. Added ui-tester as optional quality gate after UI changes.
- **verification-gate** — added "UI intact" row to Common Verification Failures table (screenshot comparison as evidence).
- **using-subteams** — version bumped to 1.5.0, description updated to 12 agents, improvement-agent model corrected to opus.

## [1.4.2] - 2026-05-03

### Fixed
- writing-plans: removed phantom "worktree created by brainstorming" reference
- finishing-branch: cleanup scope now correctly includes Options 1, 2, and 4
- brainstorming HARD-GATE: scoped to brainstorming phase only (no longer conflicts with pipeline skip)
- executing-plans + subagent-driven-dev: worktrees changed from REQUIRED to recommended
- brainstorming + writing-plans: directories created if they do not exist


## [1.4.1] - 2026-05-03

### Added
- **Standard pipeline** between Lightweight and Full: Plan → Branch → Implement → Single Review → Test → Commit → Merge. For moderate tasks (3-8 files, single-module).
- **Branch rule**: main = production, all development in feature branches. Worktrees for parallel subagent work.
- **Triple Review conflict resolution**: project conventions > general practices, structural > tactical, approach-level challenges escalate to user.
- **Brainstorming degradation clause**: after 3 non-converging rounds, summarize and offer to move forward.

### Changed
- "Maximum 3 skills" clarified to mean specialist skills on top of pipeline core.


## [1.4.0] - 2026-05-03

### Added
- **Interview-based brainstorming** — phased dialogue (Purpose → Context → Deepening) replaces old question-dump approach. No artificial limit on rounds; stop criterion is quality of understanding.
- **Orchestrator self-escalation** (Section 9) — orchestrator must escalate to user when facing blockers, impossible constraints, or decisions outside authority. Not just subagents.
- **Silent substitution prevention** — new Red Flag + Critical Rules #19-#20: never silently switch from an agreed approach. Present obstacle and options, let user decide.

### Changed
- Brainstorming skill rewritten: interview process with phases, per-round summaries, readiness checklist
- Section 7 (Dynamic User Interviewing): removed artificial "max 3 rounds" limit, aligned with brainstorming interview philosophy
- Section 9 renamed from "Subagent Escalation to User" → "Escalation to User (Subagents AND Orchestrator)"
- Red Flags Table: +2 new entries (silent substitution, autonomous handling)
- Critical Rules: +2 new rules (#19 silent substitution, #20 escalation duty)


## [1.3.0] - 2026-05-03

### Added
- **Developer agent** — implementation specialist with coding standards: modular code, minimal diffs, no god files, preserve project style, don't break other logic, document risks
- **Full Pipeline v2** in using-subteams:
  - Step 3: Plan Defense (devils-advocate reviews plan before implementation)
  - Step 4: Backup tag before implementation
  - Step 6: Triple Review (code-reviewer + architecture-guard + devils-advocate in parallel)
  - Step 10: Mandatory risk & nuance documentation
  - Step 12: Cleanup (remove backup tag, worktree, move plan to completed)
- 6 new Critical Rules (#13-18): preserve style, no god files, minimal changes, don't break logic, document risks, backup tags
- Mandatory "Risks & Nuances" section in writing-plans skill

### Changed
- Agent count: 9 → 10
- Pipeline: reactive (implement → review) → proactive (plan → defend → backup → implement → triple review → test → verify → document → finish → cleanup)
- Devils-advocate: now used twice — once for plan defense, once for code challenge

## [1.2.0] - 2026-05-03

### Fixed
- **Critical:** Renamed marketplace from "claude-subteams" to "bn-skn" to avoid cache recursion bug (#34200) when marketplace name == plugin name
- install.sh: now creates marketplace wrapper and registers in known_marketplaces.json
- install.sh: jq dependency check with warning at install time
- install.sh: git dependency check (hard fail)
- uninstall.sh: cleans known_marketplaces.json
- All scripts: migration from old marketplace name (claude-subteams@claude-subteams → claude-subteams@bn-skn)

### Changed
- Plugin key changed: `claude-subteams@claude-subteams` → `claude-subteams@bn-skn`
- Version bumped to 1.2.0
## [1.1.0] - 2026-05-02

### Fixed
- All hooks: jq availability check with graceful exit if missing
- All hooks: printf instead of echo for variable output (handles -e/-n)
- pre-commit-gate: IFS= read -r for filenames with spaces/backslashes
- install.sh/uninstall.sh: HOME safety check (prevent rm -rf on empty HOME)
- install.sh: version read from plugin.json instead of hardcoded
- install.sh: CLAUDE.md snippet checks existence, skips duplicates
- INSTALL.md: version updated to 1.1.0
- **Critical:** uninstall.sh and update.sh used wrong plugin path — could not uninstall or update after install.sh
- **Critical:** uninstall.sh used wrong enabledPlugins key (`claude-subteams` instead of `claude-subteams@claude-subteams`)
- **Critical:** pre-commit-gate failed on systems using nvm — npx not in PATH for hook shell
- pre-commit-gate matched any command containing "git commit" string (false positives)
- pre-push-check matched branch names containing "main"/"master" as substrings
- pre-commit-gate warning said "staged files exceed 200 lines" when it checks total file size
- user-prompt-check triggered on generic words (fix, test, code) — high false positive rate
- uninstall.sh now also cleans installed_plugins.json (previously left stale entry)
- update.sh now migrates from old install path automatically

### Added
- Timeout on all synchronous hooks (prevents session hang if npx/tsc freezes)
- nvm sourcing in pre-commit-gate (graceful fallback if npx not found)
- CHANGELOG.md
- `claude --plugin-dir` dev workflow in README
- Environment requirements documented (nvm, jq)

### Changed
- Version bumped to 1.1.0
- plugin.json: added repository, license, homepage fields
- Dynamic skill count check in install.sh (no hardcoded number)
- Researcher agent: documented MCP dependency for WebSearch/WebFetch

## [1.0.0] - 2026-04-10

### Added
- Initial release: 9 agents, 46 skills, 6 hooks
- install.sh, uninstall.sh, update.sh scripts
- Templates: CONVENTIONS.md, ARCHITECTURE.md, BACKLOG.md, CHANGELOG.md, ADR template
- Hooks: pre-commit-gate, pre-push-check, post-edit-check, session-start, session-end-reminder, user-prompt-check

