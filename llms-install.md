# claude-subteams — LLM Installation Protocol

> **Note:** This protocol targets the current script-based install. Once the plugin is published as a marketplace package, prefer `/plugin marketplace add bn-skn/claude-subteams` instead.

You are installing the **claude-subteams** plugin into Claude Code on the user's machine. Follow every numbered step exactly. At each gate, run the command, evaluate the output against the pass/fail criteria, and stop with a clear report if the gate fails.

---

## 0. Requirements

This protocol requires three capabilities from your harness:

1. **Shell execution** — you must be able to run arbitrary bash commands. If your harness requires per-command approval, request blanket approval for this session now before proceeding.
2. **Outbound network** — the curl path fetches from `raw.githubusercontent.com`. If outbound requests are blocked, use the clone path in step 2 instead.
3. **Bash process substitution `<()`** — the curl one-liner uses `bash <(...)`. If you are running in a restricted shell or `sh` sandbox where `<()` is unavailable, a syntax error will occur when you attempt it. **This is not an install failure — do not trigger rollback.** Switch immediately to the clone path in step 2.

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
**Fail:** not found. Stop — git is required to clone the plugin repository.

### 1d. jq (hooks dependency)

```bash
jq --version
```

**Pass:** exits 0.
**Warn (do not stop):** not found. Hooks require jq to parse JSON; install it before working on projects that use the hooks (`apt install jq` / `brew install jq` / `apk add jq`). Continue installation.

### 1e. node or python3 (JSON-edit dependency)

```bash
node --version 2>/dev/null || python3 --version
```

**Pass:** at least one exits 0.
**Fail:** neither found. Stop — the installer needs node or python3 to edit JSON config files.

### 1f. superpowers conflict check

```bash
grep -s '"superpowers@claude-plugins-official": true' "$HOME/.claude/settings.json" && echo "CONFLICT" || echo "OK"
```

**Pass:** output is `OK` or file does not exist.
**Note if CONFLICT:** claude-subteams replaces the superpowers methodology; running both causes conflicts. Ask the user whether to disable superpowers, or pass `--non-interactive` to let the installer handle it automatically. Do not abort — proceed to install.

### 1g. Already-installed check

```bash
grep -F '"claude-subteams@bn-skn"' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null && echo "ALREADY INSTALLED" || echo "FRESH INSTALL"
```

**If ALREADY INSTALLED:** tell the user the plugin is already registered. Re-running install.sh will pull the latest git commits and update timestamps, but will not perform a fresh install. Ask the user to confirm before proceeding — they may want to run `update.sh` instead (step 6). Note the outcome for your step-8 report.
**If FRESH INSTALL:** proceed to step 2 without comment.

---

## 2. Install

Two equivalent paths — choose based on your environment.

**Path A — curl (requires outbound network + Bash `<()`):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bn-skn/claude-subteams/main/scripts/install.sh)
```

This runs a remote script as your user. To inspect it first, use Path B and read `scripts/install.sh` before running.

**Path B — clone then run (no `<()` required; use when outbound curl is blocked OR when the sandbox refuses process substitution):**

```bash
git clone https://github.com/bn-skn/claude-subteams /tmp/claude-subteams
bash /tmp/claude-subteams/scripts/install.sh
```

If you attempt Path A and get a syntax error on `<(`, that is a shell limitation — switch to Path B. Do not treat it as an install failure or trigger rollback.

**Capture the full stdout** from whichever path you run. You will need it for step 8: scan for any lines beginning with `WARNING:` and note them for the user report.

**Pass:** script exits 0 and prints a line beginning with `[claude-subteams] Done.`
**Fail:** non-zero exit code. Capture the full stderr, report it to the user, and proceed to rollback (step 7) if the partial install may have left inconsistent state.

The install script is non-interactive when stdin is not a terminal. In that mode it:
- Skips the interactive superpowers-disable prompt (the plugin is still installed).
- Skips the CLAUDE.md snippet prompt (add it manually — see step 8).

---

## 3. Verification — confirm files landed

Run all three checks.

### 3a. installed_plugins.json

```bash
jq -e '.plugins["claude-subteams@bn-skn"]' "$HOME/.claude/plugins/installed_plugins.json"
```

Or without jq:

```bash
grep -F '"claude-subteams@bn-skn"' "$HOME/.claude/plugins/installed_plugins.json"
```

**Pass:** key is present.

### 3b. settings.json enabledPlugins

```bash
jq -e '.enabledPlugins["claude-subteams@bn-skn"]' "$HOME/.claude/settings.json"
```

Or without jq:

```bash
grep -F '"claude-subteams@bn-skn"' "$HOME/.claude/settings.json"
```

**Pass:** key is present and value is `true`.

### 3c. Plugin directory

```bash
ls "$HOME/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams/.claude-plugin/plugin.json"
```

**Pass:** file exists (exits 0).

If any check fails, go to step 7 (rollback), then retry from step 2.

---

## 4. Activation note — reload required

**Claude Code must reload before any skills or agents become available.**

The installing agent is running in the same session that existed before installation. Skills and agents registered by this plugin are NOT visible in the current session. All post-install verification of plugin functionality (steps 5 and 6) must happen in a new session after reload.

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

## 6. Update (future use)

If the plugin is already installed and the user wants to update:

```bash
bash "$HOME/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams/scripts/update.sh"
```

Restart Claude Code after update.

---

## 7. Rollback

If installation failed or produced inconsistent state, run the uninstall script:

```bash
bash "$HOME/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams/scripts/uninstall.sh"
```

If the plugin directory was not fully cloned (step 2 failed before clone completed), curl the uninstall script directly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bn-skn/claude-subteams/main/scripts/uninstall.sh)
```

The uninstall script removes the plugin from all three JSON files and deletes the plugin directory. After rollback, restart Claude Code, then retry from step 2.

---

## 8. Report to user

After steps 1–3 pass, compile and deliver this report. Read install.sh stdout to determine the correct status line.

**Status — choose one based on install.sh output:**

- If stdout contained lines like `Registered in installed_plugins.json` / `Added to enabledPlugins`: report **"Freshly installed."**
- If stdout contained lines like `Already registered` / `Already enabled` / `Already installed — pulling latest`: report **"Already installed; re-run updated timestamps and pulled any new commits. No fresh install occurred."**

**Files installed:** key `claude-subteams@bn-skn` present in `installed_plugins.json`, enabled in `settings.json`, plugin directory confirmed at `~/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams`.

**Functionally unverified** — the above only confirms files landed and JSON keys exist. Skills and agents have not been confirmed to load. Functional verification requires the post-reload smoke test (step 5); until then the install is functionally unverified.

**Warnings from installer (include verbatim):** scan install.sh stdout for any lines beginning with `WARNING:`. If found, quote them here. Common ones: jq missing, or a low skill-count warning. If none, write "None."

**Requires manual action:**

1. **Reload Claude Code** — run `/reload-plugins` or open a new session. Skills and agents are not active until reload.

2. **Run the smoke test** (step 5) in the reloaded session to confirm functional state.

3. **Add the CLAUDE.md activation snippet** to your project's `CLAUDE.md` (or `~/.claude/CLAUDE.md` for global activation). Copy this block:

   ```markdown
   ## Development Methodology

   For development tasks use the claude-subteams plugin (orchestrator + 12 specialized agents).
   Invoke skill "claude-subteams:using-subteams" before significant development work.
   For small fixes — act directly, invoke code-review after if logic changed.
   Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent.
   ```

   Also available at: `~/.claude/plugins/marketplaces/bn-skn/plugins/claude-subteams/templates/claudemd-snippet.md`

4. **superpowers conflict** — if detected in step 1f and not disabled during install, remove `"superpowers@claude-plugins-official": true` from `~/.claude/settings.json` manually.

**Future:** cross-model review capabilities (planned) will require separate Codex CLI authentication — not part of this installation.
