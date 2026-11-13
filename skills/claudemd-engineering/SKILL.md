---
name: claudemd-engineering
description: "Standards for writing and maintaining CLAUDE.md files: concise, prioritized, and regularly pruned. Also the one schema of the project test contract (the `subteams:test-suites v1` block that turns test checks into a commit gate) — read it before adding, generating, or editing that block."
---

# CLAUDE.md Engineering

## 1. Root CLAUDE.md Constraints

1. Maximum 200 lines for the root CLAUDE.md. NEVER exceed this.
2. Use bullets or numbered lists, not paragraphs.
3. Critical rules at the top — most important instructions first.
4. One line per rule. If a rule needs more than 2 lines of explanation, move it to a skill.
5. No duplication — if a rule exists in a skill, reference the skill, do not repeat the rule.

## 2. Content Hierarchy

Structure the root CLAUDE.md in this order:

1. **Project identity** — what this project is, in 1-2 sentences.
2. **Critical constraints** — NEVER/ALWAYS rules that apply globally.
3. **Tech stack** — languages, frameworks, key dependencies.
4. **Build/test commands** — exact commands to build, test, lint, deploy.
5. **Architecture overview** — 3-5 bullet points, not a full document.
6. **Conventions** — naming, formatting, file organization rules.
7. **References** — links to skills, docs, or external resources.

## 3. Writing Style

1. Be imperative: "Use X" not "We use X" or "You should use X."
2. Be specific: "Run `npm test`" not "Run the tests."
3. Be brief: if you cannot say it in one line, it belongs in a skill or doc.
4. NEVER include explanations of why — only what. The "why" goes in docs or skills.
5. NEVER include tutorials or onboarding content — that goes in docs/.
6. NEVER include default Claude behavior (e.g., "be helpful") — it wastes lines.

## 4. Subdirectory CLAUDE.md

1. Use subdirectory CLAUDE.md files for domain-specific rules.
2. Example: `src/api/CLAUDE.md` for API-specific conventions.
3. Subdirectory files inherit from root — do NOT repeat root rules.
4. Keep subdirectory CLAUDE.md files under 50 lines.
5. Only create a subdirectory CLAUDE.md when there are 3+ rules specific to that directory.

## 5. Rule Migration

When a rule outgrows CLAUDE.md:

1. If a rule needs examples or detailed steps, move it to a skill.
2. If a rule is about a specific technology, move it to a subdirectory CLAUDE.md.
3. If a rule is about process or workflow, move it to a skill.
4. Replace the moved rule with a one-line reference: "See skill: [skill-name]."
5. NEVER leave orphaned references — verify the target skill/file exists.

## 6. Monthly Review Checklist

1. Count lines in root CLAUDE.md. If over 200, prune immediately.
2. Check each rule: is it still accurate? Remove outdated rules.
3. Check each rule: does Claude follow it by default? Remove defaults.
4. Check each rule: is it duplicated in a skill? Remove the duplicate.
5. Check each rule: has it been violated in the past month? If never violated and never relevant, consider removing.
6. Check subdirectory CLAUDE.md files: are they still relevant to their directories?
7. Verify all skill references point to existing skills.

## 7. Anti-Patterns

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| 300-line CLAUDE.md | Exceeds working memory, rules get ignored | Prune to 200 lines, move detail to skills |
| Prose paragraphs | Hard to scan, easy to miss rules | Convert to bullet points |
| "We prefer to use..." | Wishy-washy, not actionable | "Use X" — imperative, direct |
| Duplicating skill content | Two sources of truth, will diverge | Reference the skill, do not copy |
| Including default behavior | Wastes precious lines on things Claude already does | Delete, only include overrides |
| Tutorial-style content | CLAUDE.md is config, not docs | Move to docs/ directory |
| Rules without specifics | "Write good code" is useless | "Run eslint before commit" is specific |

## 8. Critical Rules

1. NEVER exceed 200 lines in root CLAUDE.md.
2. ALWAYS put critical constraints at the top of the file.
3. MUST use bullets or numbered lists — never prose paragraphs.
4. NEVER duplicate content that exists in a skill.
5. MUST review and prune monthly.
6. NEVER include default Claude behavior — only overrides and project-specific rules.

## 9. Project Test Contract (v1)

The only full description of the contract. The process that uses it lives in `using-subteams` §6.7; the decision record is ADR-011. Do not restate the schema elsewhere — link here.

### 9.1 What it does

An optional block in the project's root `CLAUDE.md` that names the project's test suites and which files are UI, code, and tests. With it, the commit gate **blocks** a commit until the staged content has green suite runs and, above the small-change threshold, a ui-tester / test-engineer check. Without it, the same checks run and the gate only warns.

### 9.2 Where and how it is recognized

1. **File:** root `CLAUDE.md`; if `CLAUDE.md` has no marker, root `AGENTS.md`. A marker in `CLAUDE.md` — valid, `none`, or broken — means `AGENTS.md` is never read.
2. **Marker:** the line `<!-- subteams:test-suites v1 -->` as the **whole line**, starting at column 0 (trailing spaces allowed), **outside** any fenced code block. A marker inside a fence, indented, or mid-sentence is ignored — that is how documentation shows examples safely.
3. **Body:** after the marker (blank lines allowed), a fenced block (```` ``` ```` or `~~~`, info string such as `json` allowed) holding exactly one JSON object. Any other non-blank line between marker and fence, or an unclosed fence, makes the contract **broken**.
4. **Closing marker** `<!-- /subteams:test-suites -->` after the fence is a convention — write it; the reader stops at the closing fence and does not check it.
5. **Decline marker:** the whole line `<!-- subteams:test-suites none -->` = "this project does not want a contract". Nothing is enforced, the test gate stays silent (no warnings), and the contract is no longer offered. Exception: a v1 contract staged over a `none` in HEAD gets the gate's "new contract" notice.
6. **Which version governs:** the commit gate and `subteams-tests run` read the contract from the **last commit (HEAD)**; the gate, on `git commit --amend`, from HEAD^ (the commit being replaced is not the reference). With none there, `run` reads the staged one, and the gate the one in the tree the commit will record (with `-a` or paths that can include a working-tree edit); a contract that will not be committed is ignored by both. `subteams-tests status` reads HEAD, then the index. `subteams-tests` (list) and `--init-contract` read the working tree.
7. **Limits:** a `CLAUDE.md` / `AGENTS.md` over 1 MB is treated as a broken contract; a working-tree symlink resolving outside the repo is not read.
8. **Broken contract** (bad JSON, failed validation): `subteams-tests` exits 2 with the reason; the commit gate denies with the reason. No `jq` on the machine: `subteams-tests` exits 3, the gate denies ("install jq").

### 9.3 Fields

| Field | Type | Default | Meaning |
|---|---|---|---|
| `suites` | array | `[]` | Test suites. An empty list parses, but a project with UI or code needs at least one suite — test-engineer's check counts only with a green suite run. A content project without code takes the decline marker instead (9.7). |
| `suites[].name` | string, required | — | Unique. Letters, digits and `_ . : / @ + ~ -`; starts with a letter, digit, `_` or `@`. |
| `suites[].cmd` | string, required | — | One line, run as is by `bash -c` in `cwd`. Write the real command — never `… \|\| true` (the receipt records the real exit code). |
| `suites[].cwd` | string | `"."` | Relative to the repo root; no `..`, not absolute. For monorepo packages. |
| `suites[].kind` | `unit` \| `integration` \| `e2e` | `unit` | The e2e layer is required only when a `run: auto` suite of kind `e2e` covers at least one changed UI file through its `paths` (a suite without `paths` covers every file); with no such suite, ui-tester's live review with recorded screenshots (≥2) is the whole check. Label the Playwright/Cypress suite `e2e` explicitly — the default is `unit`. |
| `suites[].run` | `auto` \| `opt-in` \| `live` | `auto` | `auto` — run on every check; `opt-in` — only on explicit request; `live` — never automatically (keys, network, money). Only `auto` suites are required by the gate. |
| `suites[].paths` | array of globs | absent | Commit touches a matching file → suite required. **Absent → required for any commit that touches a non-docs file.** |
| `ui_globs` | array of globs | `[]` | UI files → ui-tester. Empty → ui-tester is never required. |
| `ui_exclude` | array of globs | `[]` | Removed from `ui_globs` (e.g. email templates, client documents, demo pages). |
| `code_globs` | array of globs | absent | Logic files → test-engineer. Absent → every non-docs file outside `ui_globs` and `test_globs`. |
| `test_globs` | array of globs | `[]` | Test files. Never in the ui/code groups — a test written by one agent does not void the other's check. They make a suite required like any file: through its `paths`, or always when it has none. |
| `app` | object | absent | Where ui-tester opens the app for the live review. |
| `app.url` | `http(s)://…` | — | Address the app answers on. |
| `app.start` | `playwright-webServer` \| `none` | — | `playwright-webServer` — ui-tester may start exactly the `webServer.command` from the project's Playwright config; `none` — the app must already be up. No other start commands exist, by design. |
| `small_change` | `{max_lines, max_files}` | `{10, 2}` | Drift allowed since the last agent check before a new one is needed. Non-negative integers; values above 10 / 2 are **clamped** to 10 / 2, with a warning — the threshold can only be lowered. Asked to raise it → refuse and explain: the value would be cut back anyway. |

**Docs-class** (never makes a suite without `paths` required, never in the default code group; it still counts as UI or code when it matches `ui_globs` or an explicit `code_globs`): `.md`, `.txt` (except `*requirements*` / `*constraints*` `.txt`), `.csv`, `.rst`, `.adoc`; root `.gitignore`, `.gitattributes`, `.editorconfig`, lockfiles; `.DS_Store`.

**Globs** are rooted at the repo root: `*` and `?` never cross `/`; `**/` = zero or more directories; a trailing `/**` = everything inside; `{a,b}` alternation (not nested). Unknown fields are ignored without a warning — check a misspelling by running `subteams-tests` and reading its output.

**Classification:** test = `test_globs`; UI = `ui_globs` − `ui_exclude` − test; code = `code_globs` − test (or the default above). Without `code_globs`, a UI file with a script extension (`.ts .tsx .js .jsx .mjs .cjs .vue .svelte .astro`) is **both** UI and code — it needs test-engineer too; markup and styles stay UI only.

**Environment:** settings a suite needs go into its `cmd`. `subteams-tests run` with a changed environment on the same line (`VAR=…` / `env` prefix, `export` / `source` before it) is denied by the commit gate, and `run` drops `npm_config_*`, `NODE_OPTIONS` and `PYTEST_ADDOPTS` from the inherited environment.

### 9.4 Example (shown inside a fence, so it never activates)

````markdown
<!-- subteams:test-suites v1 -->
```json
{
  "suites": [
    {"name": "unit", "cmd": "npm test", "kind": "unit", "run": "auto", "paths": ["src/**", "tests/**"]},
    {"name": "e2e", "cmd": "npx playwright test", "kind": "e2e", "run": "auto"},
    {"name": "smoke-live", "cmd": "npm run test:live", "kind": "integration", "run": "live"}
  ],
  "ui_globs": ["src/ui/**", "public/**"],
  "ui_exclude": ["public/emails/**"],
  "code_globs": ["src/**/*.ts"],
  "test_globs": ["**/*.test.*", "**/*.spec.*", "tests/**", "e2e/**"],
  "app": {"url": "http://localhost:3000", "start": "playwright-webServer"},
  "small_change": {"max_lines": 10, "max_files": 2}
}
```
<!-- /subteams:test-suites -->
````

### 9.5 Generating it

1. The suites and test files must exist first — the draft is built from what `subteams-tests` discovers.
2. `subteams-tests --init-contract` prints a draft JSON (stdout only; it writes nothing). It always writes `code_globs`, `test_globs` and `small_change` explicitly; it adds `app` only when a Playwright config has both `webServer` and a literal `baseURL: 'http…'`. Unlike the no-contract heuristics (only the default test command auto), the draft keeps every discovered suite `auto` except those that run a build, set `RUN_*`, run in watch / interactive mode, or are named live / canary — those are drafted `opt-in`.
3. Review before committing:
   - `run`: anything that needs keys, network, money, or a running production → `opt-in` / `live`;
   - `ui_globs`: the draft's default matches every `.html` / `.css` / `.tsx` … in the repo — narrow it to the app's directories, or `ui_exclude` the rest, so client documents and presentations do not call the ui-tester;
   - `paths`: give suites `paths` when most commits should not need them;
   - **no placeholders inside the JSON** — a value you do not know is left out (its default applies), never written as `<TEST_COMMAND>`;
   - the e2e runner's output directories (`test-results/`, `playwright-report/`) are in `.gitignore` — otherwise every e2e run changes the tree and its receipt is marked dirty.
4. Paste it into `CLAUDE.md` (in the build/test section): the marker line, the fenced JSON, the closing marker. Run `subteams-tests` — it must parse the contract and list the suites (exit 2 = broken, with the reason).
5. Stage `CLAUDE.md` alone and commit (9.6). Then rerun the suites (`subteams-tests run --all-auto`): every suite receipt is bound to the exact contract, so receipts from before the contract commit no longer count.

### 9.6 Changing it

1. A change to the contract block is **its own commit, with no other files** — the gate refuses a commit that mixes them (judged on the tree the commit will record), and tells the user the contract changed. This stops a contract being weakened in the same commit it would check. Not enforced while a merge, cherry-pick, revert or rebase is in progress — the test gate only warns then.
2. Any value change to the contract voids every suite receipt (receipts carry a hash of the contract JSON) — rerun `--all-auto` after the contract commit. Whitespace and key order do not matter.
3. `small_change` can only be lowered (9.3).
4. Removing the block returns the project to warnings only; replacing it with the decline marker silences the test gate.

### 9.7 When to add it

- **New project** via `project-scaffold`: added once the app skeleton and its tests exist (that skill's hand-off step).
- **Existing project:** offered once when `subteams-tests` finds an e2e suite or UI files (`using-subteams` §11 item 5). Declined → the decline marker, so it is not offered again.
- **Worth it** when the project has a UI or code, or when commits must not land untested — then with at least one suite (9.3 `suites`). A docs-only or content repo without code gets the decline marker.
- It counts toward the 200-line limit (Section 1) — keep `paths` and globs short.
