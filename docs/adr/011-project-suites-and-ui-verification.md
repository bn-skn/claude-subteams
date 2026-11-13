# ADR-011: Project suites and UI verification — content-bound receipts, a commit gate only under a project contract

**Status:** accepted
**Date:** 2026-11-13

## Context

An audit of 31 days of claudebot sessions (13.11.2026) found `test-engineer` and `ui-tester` never dispatched, and the project's e2e suite never run, although it was green when run by hand (31 passed / 3 skipped, 2.6 min). Root causes: "run the tests" meant the default command only; Standard and Full had no UI step; ui-tester wrote new tests but did not run existing ones and was forbidden to look at the app live; a missing Playwright MCP was read as "skip the visual check"; and the rules lived only in prose — the review gate works because it has a commit hook, tests had none. The plan went through two rounds of plan defense; round 2 replaced time- and text-based evidence with content snapshots.

## Decision

Tests and UI checks get the same structure the review gate has: plugin tools record what was verified as **content snapshots** (receipts), and the commit gate compares the commit's content with them — **blocking only in projects that opt in with a contract** in `CLAUDE.md`, and warning everywhere else.

- **R1** Two UI layers: Playwright Test (regression, tests live in the repo) + agent-browser (the agent looks at the changed screens, with screenshots).
- **R2** agent-browser, not PinchTab or Playwright MCP.
- **R3** agent-browser installs itself on first use from the plugin's lock file (`npm ci --ignore-scripts`, sha512 checked, no install scripts) into the user cache; browser = system Chrome only, otherwise the live review is honestly not done and `subteams-browser setup` is suggested (the only place Chrome is downloaded).
- **R4** Any red suite blocks delivery. "It was red before us" is the user's call.
- **R5** Live review on every UI change above the small-change threshold, on Standard and Full.
- **R6** Hard gate only under a contract; without one — warnings to the model and the user.
- **R7** claudebot's own tails (e2e in its restart gate, a weekly canary) come after the release; claudebot's contract comes inside the release, before acceptance E8.
- **R8** With a contract, a logic change requires a test-engineer receipt.
- **R9** Small-change threshold = drift allowed since the last agent check: ≤ 10 lines in ≤ 2 files, no added / deleted / renamed / binary files, counted **cumulatively** from that check, so splitting commits gains nothing. Suites never get this exemption. A contract may only lower it.
- **R10** A receipt is a content snapshot (git tree of the working tree at check time), not a time and not a command string. The gate compares it with the tree the commit will record.
- **R11** The gate reads the contract from HEAD (HEAD^ for `--amend`, also the drift base). A contract change — detected on the commit tree — is its own commit, with no other files, and the user is told. Not enforced while a merge, cherry-pick, revert or rebase is in progress: the test gate only warns then.
- **R12** (review round 1) The gate computes the tree git will record instead of refusing commit forms: `-a`, `<paths>`, `-o`, `-i`, `--pathspec-from-file` and a preceding literal `git add` / `git rm` are replayed on a temp index (`hooks/lib-commitscan.sh` + `tc_ct_*`). In exchange, under a contract the commit must be the only state-changing command of its line, with a target the gate can resolve; everything it cannot model (`-p`, command substitution other than a `$(cat <<'EOF' … EOF)` message, redirects into the repo, globs, several commits, git-dir/index overrides, an unreliable parse) is denied.

The contract schema lives only in `claudemd-engineering` §9; the process only in `using-subteams` §6.7; ui-tester's moves only in `agents/ui-tester.md`.

## Alternatives considered

- **PinchTab** — a background server built for scraping and anti-bot work, only 10–20% cheaper than agent-browser; one more daemon to keep alive.
- **Playwright MCP** for verification — expensive in tokens and regularly fails to start for the operator; its absence used to turn into "skip the visual check" (D5). Kept only as an optional preview while designing (`using-subteams` §10).
- **Screenshots only** (no regression layer) — what broke once breaks again unnoticed. The reverse, e2e only, leaves the agent blind to what it built (R1).
- **Marker written at agent start** — the bug fixed in 1.49.0: the review gate counted a review the moment the reviewer was spawned. Receipts are written on `SubagentStop` and count only with evidence, judged at check time.
- **Time-based receipts (mtime, "tests ran after the last edit")** — blind to partial staging, deletions and renames; say nothing about what is actually staged (round 2, all three critics).
- **Suite runs recognized by matching command text in PostToolUse** — spoofable (`npm test || true`), and a failing command arrives as PostToolUseFailure without a numeric exit code (spike 0.5). Suites run through `subteams-tests run`, which takes the command from the contract and records the real exit code.
- **Session-bound receipts** — a check done in one repository would count for a commit in another within the same session, and the gate breaks when the session id is absent. Receipts are keyed by repository and content instead.
- **Per-commit threshold** — bypassed by a series of small commits and blind to `commit -a`; replaced by cumulative drift between trees (R9), measured on the tree the commit will record (R12).
- **Refusing `commit -a` and `git add … && git commit` under a contract** (the design before review round 1) — refusing two forms left the other ways a line changes files before its commit open (`seq 1 200 > a.js && git commit -am x`; review fixes B13–B14). Replaced by computing the commit tree and the "only state-changing command" rule (R12).
- **Hard gate without a contract** (path heuristics) — false blocks: in claudebot 6 of 7 commits with `.html/.css` in a month were proposals, presentations and covers (R6).
- **Baseline run in a separate worktree** to tell pre-existing failures apart — a fresh worktree has no `node_modules`, build or browsers; replaced by R4.
- **`npm i agent-browser@<version>` at runtime** — resolves the dependency tree at install time without integrity pins and runs install scripts; replaced by `npm ci` from a committed lock with `--ignore-scripts` (R3).
- **Chromium from the Playwright cache** — on this machine it needs `--no-sandbox` (spike 0.4); not used.

## Consequences

- **Pro:** in a contract project the plugin behaves like CI: the commit carries exactly the content that was verified, by suites that ran green on it and by agents that checked it with evidence (e2e runs, screenshots). The evidence survives across sessions and worktrees of one repository, because it is bound to content, not to a session.
- **Pro:** UI verification no longer depends on an MCP server; both tools run through Bash for the main window and subagents alike.
- **Con:** cost. Plan estimate (not yet measured): a live review 2–5 min and 20–50K sonnet tokens; claudebot's e2e 2.6 min; in claudebot every code commit of the month was above the threshold. Measured cost goes to README after acceptance; if it is too high, the threshold is the lever to revisit.
- **Con:** under a contract the commit must be the only state-changing command of its line, and a few forms the gate cannot model are refused (R12) — each deny names the fix. `jq` becomes mandatory there (missing `jq` → deny).
- **Risk:** the gate can jam work. Mitigations: `subteams-tests status` shows what is missing before a commit attempt; the deny lists everything at once; the user's bypass `CLAUDE_SUBTEAMS_SKIP_TEST_GATE=1`; removing the contract returns the project to warnings.
- **Risk:** the agent status is read from `last_assistant_message`, or from the `SubagentHandback` call in the agent transcript with a short poll. The line is read tolerantly (leading markdown, `Status` / `Статус` in any case) but must carry exactly one of the four words; a copied `pass | …` template or no parsable line leaves a `rejected` receipt, and the deny says the agent ran without a status. If the CLI changes the format, checks stop counting — the safe side (deny, not pass).
- **Risk:** the snapshot (temp index + `git add -A` + `write-tree`) may be slow on huge repositories; the hook budget is 60 s and cheap checks run first.

## Honest residuals (not closed by this release)

- Without a contract the rules are prose plus visible warnings; D1 ("run every suite") stays prose there.
- The gate checks that an agent ran on this content with a `pass` status and left evidence — not the quality of its work. The same deliberate roughness as the review gate.
- The gate limits the model's Bash `git commit`; it is not repository protection. Commits by hand, from an IDE or through MCP are not seen. Receipts live in the user cache, and deliberate forgery of receipt files is not detected (ADR-007's line between drift and an adversary applies here too).
- In claudebot code reaches production through its restart script before any commit (R7 tail).
- A hook killed by its timeout lets Claude Code proceed without it — hence cheap checks first, 60 s budget.
- With no agent receipt yet, drift is counted from a drift **anchor** — HEAD's tree, written when a group first passes as a small change; later small commits accumulate from it (R9). Anchors expire after 14 days like every receipt.
- Project pre-commit hooks (husky, lint-staged, `core.hooksPath`) run after this gate and can change the tree it computed.
- Commit target: a literal path, a `VAR=literal` set earlier on the line, or `$(git rev-parse --show-toplevel)` (= the cwd repository) is resolved; any other target falls back to the cwd repository — denied ("use a literal path") only if that repository has a contract, otherwise allowed with a warning; commits into several repositories on one line are denied if any has a contract, else warned. A commit run from a repository without a contract whose unresolvable target lands in a contracted one escapes the gate.
- `subteams-tests status` evaluates the real index (nothing staged: the working tree); the gate evaluates the computed commit tree — they differ for `-a`, `<paths>`, `--amend`.
- A receipt snapshots the working tree: files untracked at run time are ignored by the comparison (tests ran with them present); tracked files with unstaged edits never match the commit — the deny names them with a `git stash push --keep-index --include-untracked` recipe.
- An agent working in another repository than the session's earns a receipt there only if its transcript contains that repository's absolute root — `cd ../B` work does not.
- Parsing the line is modelled, not executed: subshell scopes are flattened, `cd a || cd b` is read as both, aliases and functions are invisible (`hooks/lib-commitscan.sh` header).
- `CLAUDE_SUBTEAMS_AGENT_BROWSER` is used as given, without the version check the cache and system lookups get.
- Screenshots are not purged automatically (only receipts are).
- `systemMessage` visibility from PreToolUse is unverified (spike 0.8); `additionalContext` with "tell the user in one line" is the primary channel.

## Relation to ADR-007 and the review gate

- **ADR-007** set the plugin's honesty line: a hook-based gate contains a model that drifts, it is not a sandbox against one that sets out to defeat it. This gate makes the same claim and no stronger one. It follows the same dependency direction — hooks source `scripts/` (`lib-testclass.sh`), never the reverse.
- **Review gate (CHANGELOG 1.49.0):** the test gate extends `hooks/pre-commit-gate`, reusing its command parser (`lib-gitcmd.sh`) to find `git commit` in a Bash line — the test gate adds `lib-commitscan.sh`, a statement-level view built on the same tokenizer (R12) — and its docs-class (`NEUTRAL_RE`, moved into `lib-testclass.sh` so both gates share one definition). From 1.49.0 it inherits the lessons: evidence on `SubagentStop`, never on spawn; deny reasons to stderr so the model sees them; bypass variables read from the hook's own environment, so an inline `VAR=1 git commit` does not work. It differs in one respect: the review marker is per session, test receipts are per repository and content.

## State locations and cleanup

| What | Where | Lifetime |
|---|---|---|
| Receipts (`suite`, `shot`, `ui`, `te`, drift `anchor`) | `${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/receipts/<sha1 of canonical git-common-dir>/` | Atomic writes (temp file + `mv`, all through `tc_receipt_write`); files older than 14 days purged on every write. Worktrees of one repo share the directory — correctness comes from the content check, not from isolation |
| Recent-receipt index | `${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/receipts/_recent.log` (one line per receipt written in any store) | Append-only; lines older than 14 days dropped by an occasional rewrite |
| Agent start times | `${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/agent-starts/<agent_id>` | Kept after Stop (a resumed agent stops again without a new Start); purged after 2 days |
| agent-browser 0.43.0 | `${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/agent-browser/0.43.0/` (+ `install.log`, a transient `.lock` dir) | Until deleted by hand; a new pinned version installs next to it |
| Screenshots | `${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/screenshots/<session>/` (ui-tester convention) | Not purged automatically |
| Chrome from `subteams-browser setup` | `~/.agent-browser/browsers` (agent-browser's own location) | Until deleted by hand |
| Snapshot trees | Loose blob/tree objects in the repo's own object store; the real index is never written | Unreferenced — removed by `git gc` after its prune period |

Deleting any of the cache directories is safe at any time: lost receipts mean a rerun, a lost install means a reinstall on next use.

## Spike facts (plan Task 0, 13.11.2026)

| # | Fact | Consequence |
|---|------|-------------|
| 0.1 | The plugin's `bin/` is on the Bash PATH in the main window and in subagents, at about position 25 | Unique `subteams-*` names |
| 0.2 | A bin script gets neither `CLAUDE_PLUGIN_ROOT` nor `CLAUDE_PLUGIN_DATA`; in a live session `CLAUDE_PLUGIN_DATA` is set by another plugin (codex) | Paths from `readlink -f "$0"`; data in `~/.cache/claude-subteams` |
| 0.3 | `npm ci --ignore-scripts` installs a working 0.43.0 binary; the lock has sha512 for every platform package; ~40 MB (both gnu and musl); the JS launcher rewrites a symlink on first run | Run the platform binary directly; check integrity before first run |
| 0.4 | The system Chrome is picked up by default; Playwright's Chromium needs `--no-sandbox` | System Chrome only, otherwise degrade + `setup` |
| 0.5 | PostToolUse(Bash) fires in subagents; a non-zero exit arrives as PostToolUseFailure without a numeric code | Suite receipts via `subteams-tests run`, not PostToolUse |
| 0.6 | SubagentStop carries `agent_transcript_path`, `agent_type`; `last_assistant_message` is present except when the agent finishes via `SubagentHandback`; the transcript is not fully written when the hook fires | Status from `last_assistant_message`, else from `SubagentHandback` in the transcript with a short poll |
| 0.7 | `bin/` is supported since Claude Code 2.1.91 (practically ≥ 2.1.284) | Requirement in README |
| 0.8 | Visibility of `systemMessage` from PreToolUse — **not verified** | Check on the first live run (acceptance E12); primary channel `additionalContext` |

## Related

Plan: `2026-11-13-testing-ui-1.50.0.md` in `docs/plans/` (`active/` while in work, then `completed/`; §3 decisions, §4 residuals, §10 plan defense). Files: `scripts/lib-testclass.sh`, `scripts/discover-tests.sh`, `bin/subteams-tests`, `bin/subteams-browser`, `deps/agent-browser/`, `hooks/pre-commit-gate`, `hooks/lib-commitscan.sh`, `hooks/subagent-rails`, `agents/ui-tester.md`, `agents/test-engineer.md`, `skills/using-subteams/SKILL.md` §6.7, `skills/claudemd-engineering/SKILL.md` §9. Extends ADR-007 (same threat-model line); builds on the 1.49.0 review gate.
