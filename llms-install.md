# claude-subteams — LLM Installation Protocol

You are installing the **claude-subteams** plugin into Claude Code on the user's machine via the official plugin marketplace. Follow every numbered step exactly. At each gate, run the command, evaluate the output against the pass/fail criteria, and stop with a clear report if the gate fails.

---

## 0. Requirements

This protocol requires three capabilities from your harness:

1. **Shell execution** — you must be able to run arbitrary bash commands. If your harness requires per-command approval, request blanket approval for this session now before proceeding.
2. **Claude Code CLI** — the `claude` binary must be on PATH. If it is not, the plugin has nothing to load into.
3. **Private repo auth** — this repo is private. The user's git credentials must be configured so `git clone git@github.com:bn-skn/claude-subteams` (or the HTTPS equivalent) succeeds without prompting. Claude Code uses the machine's existing git/gh credentials when cloning marketplace repos.

If you cannot satisfy requirement 1, stop and tell the user their harness does not support shell-based installation. They can run the installer manually.

---

## 1. Pre-flight checks

### 1a. Operating system

```bash
uname -s
```

**Pass:** output is `Linux` or `Darwin`.
**Fail:** any other value. Stop — this installer is not supported on Windows (use WSL2).

### 1b. Claude Code presence

```bash
claude --version
```

**Pass:** exits 0 and prints a version string.
**Fail:** command not found. Claude Code CLI is not on this shell's PATH. Before stopping, confirm with the user: Claude Code may be installed as an IDE extension with the CLI not exposed to this shell. If the user confirms it is present, proceed. If Claude Code is genuinely absent, stop — the plugin has nothing to load into.

### 1c. git

```bash
git --version
```

**Pass:** exits 0.
**Fail:** not found. Stop — git is required for marketplace cloning.

### 1d. GitHub auth (private repo)

```bash
gh auth status 2>&1 | head -5
```

**Pass:** output includes `Logged in to github.com` (or similar confirmation).
**Fail / gh not found:** warn the user that git credentials for `github.com/bn-skn` must be configured before the marketplace add will work. Options:

- `gh auth login && gh auth setup-git`
- Set `GITHUB_TOKEN` in the environment
- Manually configure `~/.netrc` or SSH key

Do not stop — proceed, but note the auth status for the step-7 report.

### 1e. jq (hooks dependency)

```bash
jq --version
```

**Pass:** exits 0.
**Warn (do not stop):** not found. Hooks require jq to parse JSON; install it before working on projects that use the hooks (`apt install jq` / `brew install jq` / `apk add jq`). Continue installation.

### 1f. superpowers conflict check

```bash
grep -s '"superpowers@claude-plugins-official": true' "$HOME/.claude/settings.json" && echo "CONFLICT" || echo "OK"
```

**Pass:** output is `OK` or file does not exist.
**Note if CONFLICT:** claude-subteams replaces the superpowers methodology; running both causes conflicts. Ask the user whether to disable superpowers by removing that key from `settings.json`. Do not abort — proceed to install.

### 1g. Already-installed check

```bash
claude plugin list 2>/dev/null | grep -F "claude-subteams" && echo "ALREADY INSTALLED" || echo "FRESH INSTALL"
```

**If ALREADY INSTALLED:** tell the user the plugin is already registered. Ask whether to reinstall or run an update (`claude plugin marketplace update articortex`) instead. Note the outcome for your step-7 report.
**If FRESH INSTALL:** proceed to step 2 without comment.

---

## 2. Install

### 2a. Add the marketplace

```bash
claude plugin marketplace add bn-skn/claude-subteams
```

This registers the `articortex` marketplace (defined in `.claude-plugin/marketplace.json` at the repo root). Claude Code clones the repo using the machine's git credentials.

**Pass:** exits 0. Output should confirm the marketplace was added.
**If "already added" / non-zero:** check whether the marketplace is already registered:

```bash
claude plugin marketplace list 2>/dev/null | grep -F "articortex"
```

If it is listed, proceed to step 2b — the marketplace add is idempotent.

### 2b. Install the plugin

```bash
claude plugin install claude-subteams@articortex
```

**Capture the full stdout.** Scan for any lines beginning with `WARNING:` and note them for the step-7 report.

**Pass:** exits 0.
**Fail:** non-zero exit code. Capture the full stderr and report it to the user. Common causes:
- Auth failure cloning the private repo (step 1d).
- `claude plugin` subcommand not recognized — run `claude plugin --help` to confirm available subcommands and adjust accordingly.

---

## 3. Verification — confirm install registered

### 3a. Plugin listed by the CLI

```bash
claude plugin list 2>/dev/null | grep -F "claude-subteams@articortex" && echo "OK" || echo "MISSING"
```

**Pass:** `OK` — the CLI confirms `claude-subteams@articortex` is registered.

This is the authoritative check. The CLI is the source of truth for what is installed, regardless of where on disk Claude Code placed the cloned files.

### 3b. Plugin directory sanity (informational only — do NOT trigger rollback on this alone)

```bash
find "$HOME/.claude/plugins" -name "plugin.json" 2>/dev/null | grep "claude-subteams"
```

**Pass:** any path containing `claude-subteams` is printed.

Note: with `source: "./"` in the marketplace manifest, Claude Code clones the repo directly into the marketplace root — the directory layout may not contain a `plugins/claude-subteams/` segment. If 3b returns nothing but 3a passed, the install is still good; 3a is definitive.

If **3a** fails (plugin not listed), go to step 6 (rollback), then retry from step 2.

---

## 4. Activation note — reload required

**Claude Code must reload before any skills or agents become available.**

The installing agent is running in the same session that existed before installation. Skills and agents registered by this plugin are NOT visible in the current session. All post-install verification of plugin functionality (step 5) must happen in a new session after reload.

Tell the user to:

1. Run `/reload-plugins` inside Claude Code, **or** start a new Claude Code session.
2. After that, proceed to the smoke test in a fresh context.

You cannot verify plugin functionality from within the same pre-reload session. Stop here. Tell the user to reload, then run the step-5 smoke test — or paste step 5 back to you in a fresh session after reload. The user owns this boundary.

---

## 5. Smoke test (post-reload session only)

**Run this only after the reload from step 4.**

### 5a. Skills listing

In Claude Code, run:

```
/skills
```

**Pass:** output contains `claude-subteams:using-subteams`.

### 5b. Agents listing

In Claude Code, run:

```
/agents
```

**Pass:** output contains `claude-subteams:code-reviewer`.

### 5c. Optional functional test

Create a minimal synthetic file and dispatch the code-reviewer agent:

```
Review this file using the claude-subteams:code-reviewer agent:

function add(a, b) { return a + b }
```

**Pass:** the code-reviewer agent responds with a structured review. The exact content does not matter — any coherent response confirms the agent dispatch pipeline is working.

---

## 6. Rollback

If installation failed or produced inconsistent state:

```bash
claude plugin uninstall claude-subteams@articortex 2>/dev/null || true
claude plugin marketplace remove articortex 2>/dev/null || true
```

After rollback, restart Claude Code, then retry from step 2.

---

## 7. Report to user

After steps 1–3 pass, compile and deliver this report.

**Status — choose one:**

- If step 2b installed freshly: **"Freshly installed."**
- If already installed (step 1g): **"Already installed; no reinstall performed."**

**Files installed:** plugin directory confirmed, plugin listed in `claude plugin list`.

**Functionally unverified** — the above only confirms files landed. Skills and agents have not been confirmed to load. Functional verification requires the post-reload smoke test (step 5); until then the install is functionally unverified.

**Warnings from installer (include verbatim):** scan step 2b stdout for any `WARNING:` lines. If none, write "None."

**Auth status:** report what you found in step 1d. If credentials were absent, remind the user to configure git/gh auth for future updates.

**Requires manual action:**

1. **Reload Claude Code** — run `/reload-plugins` or open a new session. Skills and agents are not active until reload.

2. **Run the smoke test** (step 5) in the reloaded session to confirm functional state.

3. **Add the CLAUDE.md activation snippet** to your project's `CLAUDE.md` (or `~/.claude/CLAUDE.md` for global activation). Copy this block:

   ```markdown
   ## Development Methodology

   For development tasks use the claude-subteams plugin (orchestrator + specialized sub-team agents).
   Invoke skill "claude-subteams:using-subteams" before significant development work.
   For small fixes — act directly, invoke code-review after if logic changed.
   Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent, gpt-code-reviewer, gpt-devils-advocate.
   ```

   Also available at: `templates/claudemd-snippet.md` inside the plugin's installed directory (locate with `find "$HOME/.claude/plugins" -name "claudemd-snippet.md" 2>/dev/null`).

4. **superpowers conflict** — if detected in step 1f and not disabled, remove `"superpowers@claude-plugins-official": true` from `~/.claude/settings.json` manually.

**Future:** cross-model review capabilities require separate Codex CLI authentication — not part of this installation.
