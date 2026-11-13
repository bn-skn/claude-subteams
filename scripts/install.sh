#!/bin/bash
# Install claude-subteams via the official Claude Code plugin marketplace.
#
# Primary path (inside Claude Code):
#   /plugin marketplace add bn-skn/claude-subteams
#   /plugin install claude-subteams@articortex
#
# This script is a convenience wrapper for shell environments.
# Requires: claude CLI on PATH, git, network access to github.com

set -euo pipefail

# --- Safety checks ------------------------------------------------------------

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  echo "[claude-subteams] ERROR: \$HOME is unset or root. Aborting." >&2
  exit 1
fi

MARKETPLACE_NAME="articortex"
PLUGIN_NAME="claude-subteams"
REPO="bn-skn/claude-subteams"

echo "[claude-subteams] Installing..."

# --- Check dependencies -------------------------------------------------------

if ! command -v claude &>/dev/null; then
  echo "[claude-subteams] ERROR: 'claude' CLI not found on PATH." >&2
  echo "  Install Claude Code CLI first: https://docs.anthropic.com/en/docs/claude-code" >&2
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "[claude-subteams] ERROR: 'git' is required for marketplace cloning." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "[claude-subteams] WARNING: jq not found. Plugin hooks require jq to parse JSON."
  echo "  Install: apt install jq / brew install jq / apk add jq"
fi

# --- Add marketplace (idempotent) ---------------------------------------------

echo "[claude-subteams] Registering marketplace '$MARKETPLACE_NAME'..."

# Check if already added; tolerate non-zero from 'list' gracefully.
ALREADY_ADDED=false
if claude plugin marketplace list 2>/dev/null | grep -qF "$MARKETPLACE_NAME"; then
  ALREADY_ADDED=true
  echo "[claude-subteams] Marketplace '$MARKETPLACE_NAME' already registered — skipping add."
fi

if [ "$ALREADY_ADDED" = false ]; then
  # NOTE: verify exact subcommand against 'claude plugin marketplace --help'
  # if this fails with "unknown command", the CLI version may differ.
  if ! claude plugin marketplace add "$REPO"; then
    echo "[claude-subteams] ERROR: marketplace add failed." >&2
    echo "  Check network access to github.com and that the 'claude' CLI supports" >&2
    echo "  'plugin marketplace add' (run: claude plugin marketplace --help)." >&2
    exit 1
  fi
fi

# --- Install plugin (idempotent) ----------------------------------------------

PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE_NAME}"
if claude plugin list 2>/dev/null | grep -qF "$PLUGIN_KEY"; then
  echo "[claude-subteams] Plugin '$PLUGIN_KEY' already installed — skipping."
else
  echo "[claude-subteams] Installing plugin $PLUGIN_KEY..."
  # NOTE: verify exact subcommand against 'claude plugin --help' if this fails.
  claude plugin install "$PLUGIN_KEY"
fi

# --- Warn about superpowers conflict ------------------------------------------

# Best-effort check across settings.json and installed_plugins.json (non-fatal).
if grep -qs '"superpowers@claude-plugins-official": true' \
     "$HOME/.claude/settings.json" \
     "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; then
  echo ""
  echo "[claude-subteams] WARNING: The 'superpowers' plugin appears to be enabled."
  echo "  claude-subteams replaces superpowers methodology."
  echo "  Running both may cause conflicts."
  echo "  To disable: remove 'superpowers@claude-plugins-official' from ~/.claude/settings.json"
fi

# --- CLAUDE.md snippet (interactive only) -------------------------------------

if [ -t 0 ]; then
  echo ""
  if [ -f "CLAUDE.md" ] && grep -q "claude-subteams" "CLAUDE.md" 2>/dev/null; then
    echo "[claude-subteams] Activation snippet already in ./CLAUDE.md — skipping."
  elif [ -f "CLAUDE.md" ]; then
    read -r -p "[claude-subteams] Add activation snippet to ./CLAUDE.md? [y/N] " ADD_SNIPPET
    if [[ "${ADD_SNIPPET,,}" == "y" ]]; then
      # Snippet is embedded here — no dependency on the installed plugin tree path.
      cat >> "CLAUDE.md" << 'SNIPPET'

## Development Methodology

For development tasks use the claude-subteams plugin (orchestrator + specialized sub-team agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed. Any logic change gets code-reviewer (and devils-advocate for non-trivial logic) — no "it's just one line" exemption.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent, gpt-code-reviewer, gpt-devils-advocate, prompt-engineer, agent-architect, gemini-analyst, gemini-code-reviewer, gemini-design-critic, gemini-frontend.
Cross-model review (gpt-* via Codex, gemini-* via the `agy` CLI) runs on the Full pipeline, on a cross-review trigger, and on request — not by default on Standard. Native Claude agents stay primary — cross-model findings never override them, and an unavailable lane degrades without blocking but is always stated.
Building/editing agents, prompts, skills, or multi-agent systems → invoke agent-architect + prompt-engineer + prompt-evaluator (using-subteams Section 6.5).
Test contract (optional): a `subteams:test-suites v1` block in this file names the project's test suites and UI/code files and turns the test checks into a commit gate — schema and how to generate it: skill `claude-subteams:claudemd-engineering` §9; process: `using-subteams` §6.7.
Running several Claude Code instances on one repo → set `CLAUDE_SUBTEAMS_MULTI_INSTANCE=1` and follow the `multi-instance` skill: claim files before editing (and claim them yourself before dispatching a subagent to edit them), serialize heavy gates with `gate-lock`, commit/merge under `commit-lock`, land branches via its Merge Protocol (§7). **`gate-lock` always wraps `commit-lock`, never the reverse** — wrapping a whole gate+merge sequence in one `commit-lock` is the inverted order and deadlocks. Isolate work in worktrees via `using-git-worktrees`; never `npm install` from a worktree that shares `node_modules`.
Two always-on rules that must NOT be left to a skill trigger — keep them in this file verbatim: (1) the user's own past is never searched on the web — it lives in your memory store and knowledge base; (2) a library already installed in the project is CODE, not the outside world — read the installed package and its version-matched docs before going online. Both are cheap to state and expensive to lose.

Message shape is a REFLEX, not a skill call — keep these verbatim in this file: short and readable, plain text beats heavy markdown; a long result opens with a summary, then offer to expand; never forward a subagent's or generator's raw output unread — if the person asks for it raw, hand it over untouched but read it first, and flag broken/empty/truncated output in one line ABOVE it. Measured: a skill carrying these fired on 2 of 5 human-facing deliveries and was not reproducible on identical input — the platform does not invoke a skill for what the model already does unaided.

Two cross-cutting habits live in the plugin, not in this file: invoke `claude-subteams:context-gaps` when the user refers to something as already known that is NOT in your context (classify the gap — shared past / code / outside world — and fetch from the source that owns it; never merge similar-but-different recall hits), and `claude-subteams:delivering-to-user` before an expensive delivery — a client document, a render, a diff, a report, a subagent's output you are about to pass on (one deliberate pass as the recipient; the depth of what to check lives there, the reflex above lives here). Instance-specific bindings — which memory store, which notification channel, which voice mode — stay in this file.
SNIPPET
      echo "[claude-subteams] Snippet appended to ./CLAUDE.md."
    fi
  else
    echo "[claude-subteams] No CLAUDE.md in current directory — snippet not added."
    echo "  Add it manually later. See README.md for the snippet."
  fi
fi

# --- Done ---------------------------------------------------------------------

echo ""
echo "[claude-subteams] Done. Restart Claude Code (/reload-plugins or new session)."
