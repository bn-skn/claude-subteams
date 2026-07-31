---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - creates isolated git worktrees with smart directory selection, safety verification, and shared-node_modules setup via ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-setup.sh
---

# Using Git Worktrees

## Overview

Git worktrees create isolated workspaces sharing the same repository, allowing work on multiple branches simultaneously without switching.

**Core principle:** Systematic directory selection + safety verification = reliable isolation.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Directory Selection Process

Follow this priority order:

### 1. Check Existing Directories

```bash
# Check in priority order
ls -d .claude/worktrees 2>/dev/null   # Native Claude Code convention (`claude --worktree <name>`)
ls -d .worktrees 2>/dev/null          # Preferred fallback (hidden)
ls -d worktrees 2>/dev/null           # Alternative
```

**If found:** Use that directory. `.claude/worktrees` wins if the project already uses the
native `claude --worktree <name>` mechanism (it creates worktrees there on a
`worktree-<name>` branch automatically) — prefer riding that convention over inventing a
parallel one. Otherwise, if both `.worktrees` and `worktrees` exist, `.worktrees` wins.

### 2. Check CLAUDE.md

```bash
grep -i "worktree.*director" CLAUDE.md 2>/dev/null
```

**If preference specified:** Use it without asking.

### 3. Ask User

If no directory exists and no CLAUDE.md preference:

```
No worktree directory found. Where should I create worktrees?

1. .worktrees/ (project-local, hidden)
2. ~/.config/claude-subteams/worktrees/<project-name>/ (global location)

Which would you prefer?
```

## Safety Verification

### For Project-Local Directories (.claude/worktrees, .worktrees, or worktrees)

**MUST verify the directory chosen in Directory Selection above is ignored — not
"any one of the three candidates".** The three paths are alternatives, not a set that's
safe together: chaining them with `||` reports success the moment the FIRST one happens
to be ignored, even if that's not the one you actually picked. E.g. `.claude/worktrees`
being pre-ignored short-circuits the check to "safe" while the `.worktrees` directory you
actually selected — and are about to create the worktree in — was never checked at all.

```bash
# Replace <chosen-dir> with whatever Directory Selection actually picked
# (.claude/worktrees, .worktrees, worktrees, or a custom path) — check that one only.
git check-ignore -q "<chosen-dir>" 2>/dev/null
```

**If NOT ignored:**
1. Add appropriate line to .gitignore
2. Commit the change
3. Proceed with worktree creation

**Why critical:** An untracked worktree directory shows up as untracked clutter in `git
status` for the main checkout, and risks accidentally being `git add`-ed or committed. This
is not hypothetical — `.claude/worktrees/` not being gitignored has actually happened (found
in claudebot). Don't assume the native convention is pre-ignored; check it exactly like any
other candidate directory.

### For Global Directory (~/.config/claude-subteams/worktrees)

No .gitignore verification needed - outside project entirely.

## Creation Steps

### 1. Detect Project Name

```bash
project=$(basename "$(git rev-parse --show-toplevel)")
```

### 2. Create Worktree

Two ways to create one — which applies follows from the directory choice in step 1.

**Native (`.claude/worktrees/`):**

```bash
claude --worktree <name>   # or: claude -w <name>
```

Creates `.claude/worktrees/<name>/` directly, on branch **`worktree-<name>`** — NOT
`<name>` itself. This branch-naming convention is the native mechanism's own and differs
from the manual path below; don't assume the branch is called `<name>` when reporting
location or opening a PR. Confirmed live on claudebot (Claude Code CLI 2.1.220, `-w`/
`--worktree` present in `--help`): `claude -w probe-wi` produced
`.claude/worktrees/probe-wi/` on branch `worktree-probe-wi`.

**Must carry a prompt when run from an agent's Bash tool.** Per its own `--help` text,
`claude --worktree <name>` creates a worktree **for a new session** — it isn't a
standalone worktree-management command, it launches Claude Code. Reproduced live: `claude
-w probe2 </dev/null` (no prompt, no stdin) → `rc=1, Error: Input must be provided either
through stdin or as a prompt argument when using --print`, and the worktree is already
CREATED AND LOCKED before that failure — the command as documented leaves locked garbage
behind if run bare. Always pass a prompt: `claude -w <name> -p '<prompt>'`. If you only
need the directory and don't want a new session, use the manual path below instead.

**Manual (`.worktrees/`, `worktrees/`, or a custom location):**

```bash
git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

Here the branch is exactly whatever you pass to `-b` — full control, no `worktree-`
prefix.

### 3. Secrets: `.worktreeinclude`

A fresh worktree is a plain `git checkout` — it does **not** get gitignored files like
`.env`. Claude Code's `.worktreeinclude` (same syntax as `.gitignore`, lives at the repo
root) closes that gap: any gitignored path it lists gets copied into a new worktree
automatically. The typical, close to only, use is `.env`.

> **NATIVE PATH ONLY — this is the trap.** `.worktreeinclude` is a *Claude Code* feature,
> not a git one. It fires for `claude --worktree`/`-w`; a manual `git worktree add` copies
> **nothing** and never so much as mentions the file. Verified live on claudebot — same
> repo, same `.worktreeinclude` containing just `.env`: native → a full, correct `.env`
> (170 lines) in the new worktree; manual → **no `.env` at all**.
>
> This matters because the failure is silent and misattributed: the project starts, then
> half-works or degrades because a key is missing, and nothing points at the worktree —
> the main checkout is fine, after all. **Created the worktree manually and the project
> needs `.env`? Copy or symlink it yourself**, minding the same trust boundary below.

**Trust boundary this creates:** every worktree that gets a copied `.env` now holds LIVE
secrets, on disk, under whatever permissions that directory has. Treat that worktree with
the same care as the main checkout from a secrets standpoint — don't relax file permissions
just because it's "just a dev copy". `.worktreeinclude` is for secrets and small config
only. Do **not** add `node_modules` (megabytes-to-gigabytes, see step 4) or runtime state
like `store/`/a live database to it — those aren't gitignore-and-copy candidates, they're
either shared (§ below) or explicitly excluded from worktree isolation entirely.

### 4. Run Project Setup

Auto-detect and run appropriate setup. **Node.js is the one ecosystem where "just install"
is the wrong default** — call the shared helper instead:

```bash
if [ -f package.json ]; then
  SETUP="${CLAUDE_PLUGIN_ROOT:-}/scripts/worktree-setup.sh"
  [ -f "$SETUP" ] || SETUP=$(ls -d "$HOME"/.claude/plugins/cache/*/claude-subteams/*/scripts/worktree-setup.sh 2>/dev/null | sort -V | tail -1)
  [ -f "$SETUP" ] || { echo "worktree-setup.sh not found — STOP, do not fall back to npm install in this worktree"; exit 1; }
  bash "$SETUP"
fi

# Rust / Python / Go: cheap enough to install per-worktree, do it directly
if [ -f Cargo.toml ]; then cargo build; fi
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi
if [ -f go.mod ]; then go mod download; fi
```

`worktree-setup.sh` lives in **this plugin**, not the target repo. `${CLAUDE_PLUGIN_ROOT}`
is the right way to reach it (same convention as `skills/multi-instance/SKILL.md`) — but
it's set for hooks and **not guaranteed to be set in an agent's Bash tool environment**;
confirmed live. A bare `${CLAUDE_PLUGIN_ROOT}/scripts/...` then resolves to an empty path
and fails. That's why the snippet above has a fallback (glob the plugin cache directly)
and, more importantly, a hard stop if BOTH fail: an agent that just sees a bare
"not found" here tends to improvise `npm install` right in the worktree instead — the
exact shared-`node_modules` mutation risk this step exists to prevent (see Red Flags
below for the rule and why). No path argument is passed to the script either: by this
point you're already `cd`'d into the worktree (step 2's manual path does it explicitly;
native `claude -w` leaves you there by construction), and the script defaults to `$PWD`.

`worktree-setup.sh` **symlinks** the worktree's `node_modules` to the main checkout's
instead of installing a fresh copy, guards against a Node-version/ABI mismatch (loud
warning, refuses to link, never crashes, never runs `npm ci` for you — only tells you
to), and cleans out any inherited `*.tsbuildinfo`. See the script's own header comment for
full behavior and exit codes; it's idempotent, safe to call again. **The one place the
"why never `npm install`/`npm ci` in a worktree" rule is stated is Red Flags below — don't
repeat it here or anywhere else in this file.**

### 5. Verify Clean Baseline

Run tests to ensure worktree starts clean:

```bash
# Use project-appropriate command
npm test / cargo test / pytest / go test ./...
```

**Before this first run, confirm the test suite is hermetic** — that it exercises an
in-memory/tmp database and mocked external calls, not anything live. Step 3 just copied a
`.worktreeinclude`d `.env` into this worktree, which for most projects means LIVE
secrets/credentials are now on disk here. Running a non-hermetic suite immediately after
means "point the project's real tests at the project's real database/API using the
project's real keys" — in a project without hermetic tests, that's a test run against
production. If the suite isn't hermetic, swap in throwaway values in this worktree's
`.env` copy before running it, not the other way around.

**If tests fail:** Report failures, ask whether to proceed or investigate.
**If tests pass:** Report ready.

**With multiple instances active:** a heavy gate (tsc + vitest + a canary/service boot) is
CPU/RAM-expensive enough that running it concurrently in 4-5 worktrees on one box will
starve them all. Wrap the baseline test command above in the lock:

```bash
coord.sh gate-lock -- npm test   # or the project-appropriate test command from above
```

See the `multi-instance` skill for the full protocol; this skill only runs the baseline
check, it doesn't own the merge/gate sequencing.

### 6. Report Location

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## What a Worktree Does NOT Isolate

A linked worktree shares the repository's git objects and refs with every other worktree,
but several things are **not** per-worktree at all — know these before assuming isolation
covers everything:

- **`node_modules`** — shared by design via the symlink from step 4. A `npm install` in one
  worktree is a `npm install` for all of them (and for the main checkout).
- **Runtime database (SQLite/WAL or similar)** — WAL supports many readers but ONE writer.
  A worktree may **read** the live database freely; it must **never write** to it while the
  main checkout's service is running (writer-lock contention → `database is locked`,
  checkpoint starvation). Any write that belongs in the live DB (schema migration, marking
  something applied, dropping a table) happens **only from the main checkout**, at the
  merge/integration step — not from a worktree mid-development. For tests, use a throwaway
  copy of the database, never the live file.
- **`.env` / secrets** — copied in by `.worktreeinclude`, not generated fresh; see step 3
  above for the trust implications.
- **Live skills and git hooks** — the skills directory a running agent actually reads is the
  main checkout's; a worktree's copy is a staged draft until merged. Git hooks live under
  one shared hooks directory for the whole repository (`--git-common-dir`), so a hook
  *installer* run from a worktree would install hooks for the main checkout too, before
  those changes have even merged — always run a hook installer from the main checkout.
- **Build cache (`*.tsbuildinfo` and similar incremental caches)** — keyed to the source
  tree it was built from; stale the moment it's read from a different branch.
  `worktree-setup.sh` deletes any inherited copy it finds.

## Cleanup: Removing a Worktree

**Worktrees created via `claude --worktree`/`-w` are LOCKED, and the lock outlives the
session.** After the Claude session that created it exits, a plain `git worktree remove`
fails with:

```
fatal: cannot remove a locked working tree, lock reason: claude session <name> (pid NNNN start ...)
use 'remove -f -f' to override or unlock first
```

The pid named in the lock reason is almost always already dead by the time you're cleaning
up — this message *reads* like "someone else is still using it" when actually no one is.
Confirmed live on claudebot. Verified safe removal order:

1. **Confirm the pid really is dead** — `kill -0 <pid>` (the pid from the lock reason). If
   that succeeds, something IS still running against this worktree — stop, don't remove it.
2. `git worktree unlock <path>`
3. `git worktree remove --force <path>`, then `git worktree prune`
4. `git branch -D <branch>` — git refuses to delete a branch that's still checked out by a
   worktree ("used by worktree"), so this must come AFTER step 3, never before.

Worktrees created manually via `git worktree add` aren't locked — skip step 2 (nothing to
unlock) and go straight from step 1 to step 3, then step 4.

This section is worktree/lock mechanics only. Whether a branch is actually done, ready to
merge, and what happens to its PR is a judgment call owned by
**claude-subteams:finishing-branch** — use that skill for the decision, this procedure for
the `git worktree`/lock plumbing it doesn't cover.

## Red Flags

**NEVER:**
- Create worktree without verifying it is ignored (project-local)
- Skip baseline test verification
- Proceed with failing tests without asking
- Assume directory location when ambiguous
- Skip CLAUDE.md check
- Run `npm install`/`npm ci` from a worktree when `node_modules` is shared with the main
  checkout via symlink — it mutates the SHARED copy, which may back a live service
- `npm rebuild` a shared `node_modules` to "fix" an ABI mismatch — that breaks it for
  everyone else using it; get an isolated `node_modules` in the worktree instead (`npm ci`)
- Write to the live runtime database from a worktree — read-only while the main checkout's
  service is running; writes happen from the main checkout at merge/integration time
- Install git hooks from a worktree — the hooks directory is shared repo-wide
  (`--git-common-dir`); always run a hook installer from the main checkout
- Put `node_modules` or runtime state (`store/`, a live DB) into `.worktreeinclude` — it's
  for secrets/small config, not large shared or stateful directories
- Force-remove a locked worktree without first confirming the pid in the lock reason is
  actually dead (`kill -0 <pid>`) — a stale-looking lock isn't proof no one is using it
- Delete a worktree's branch before removing the worktree itself — git refuses while it's
  still checked out ("used by worktree")
- Assume a `claude --worktree <name>`/`-w <name>` worktree's branch is called `<name>` — it
  is `worktree-<name>`

**ALWAYS:**
- Follow directory priority: existing > CLAUDE.md > ask
- Verify directory is ignored for project-local
- Auto-detect and run project setup — for Node.js, via `scripts/worktree-setup.sh`, never a
  raw `npm install` in the worktree
- Verify clean test baseline
- Unlock a native (`claude --worktree`) worktree before removing it (`git worktree unlock`
  then `remove --force`) — see the Cleanup section above

## Integration

**Called by:**
- **claude-subteams:brainstorming** - when design is approved and implementation follows
- **claude-subteams:subagent-driven-dev** - before executing any tasks
- **claude-subteams:executing-plans** - before executing any tasks

**Pairs with:**
- **claude-subteams:finishing-branch** - for cleanup after work complete
- **claude-subteams:multi-instance** - serializes the baseline gate (step 5) across concurrent instances via `coord.sh gate-lock`
