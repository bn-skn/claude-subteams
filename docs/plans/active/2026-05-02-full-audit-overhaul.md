# Plan: Full Audit Overhaul

**Date:** 2026-05-02
**Branch:** fix/full-audit-overhaul
**Status:** active

## Context

Plugin claude-subteams (14 agents, 53 skills, 6 hooks) has critical bugs preventing clean install/uninstall/update on fresh Claude Code instances. Issues discovered through code audit + production experience.

## Critical Fixes (C1-C4)

### C1. uninstall.sh path mismatch — RESOLVED
- **File:** `scripts/uninstall.sh:6`
- **Bug:** Uses `$HOME/.claude/plugins/claude-subteams` but install.sh puts plugin at `$HOME/.claude/plugins/marketplaces/claude-subteams/plugins/claude-subteams`
- **Resolution:** Resolved by the v1.14.0 marketplace migration — install.sh/update.sh/uninstall.sh were rewritten as thin CLI wrappers; the old path/key mismatches no longer exist.

### C2. update.sh same path mismatch — RESOLVED
- **File:** `scripts/update.sh:6`
- **Bug:** Same wrong path, update always fails
- **Resolution:** Resolved by the v1.14.0 marketplace migration — install.sh/update.sh/uninstall.sh were rewritten as thin CLI wrappers; the old path/key mismatches no longer exist.

### C3. uninstall.sh enabledPlugins key mismatch — RESOLVED
- **File:** `scripts/uninstall.sh:14-19`
- **Bug:** install.sh writes key `claude-subteams@claude-subteams`, uninstall tries to delete `claude-subteams`
- **Resolution:** Resolved by the v1.14.0 marketplace migration — install.sh/update.sh/uninstall.sh were rewritten as thin CLI wrappers; the old path/key mismatches no longer exist.

### C4. pre-commit-gate: npx not found without nvm
- **File:** `hooks/pre-commit-gate:17`
- **Bug:** No nvm sourcing in hook shell — npx not in PATH
- **Fix:** Add nvm sourcing to all hooks that need node; also add SessionStart hook for CLAUDE_ENV_FILE PATH setup

## Important Fixes (I1-I6)

### I1. pre-commit-gate: loose git commit regex
- **File:** `hooks/pre-commit-gate:9`
- **Fix:** Tighten regex to `grep -qE '^\s*(git\s+commit|git\s+-C\s+\S+\s+commit)'`

### I2. pre-push-check: loose main/master regex
- **File:** `hooks/pre-push-check:12`
- **Fix:** Use word boundary: `grep -qEw "main|master"` or `grep -qE '\b(main|master)\b'`

### I3. pre-commit-gate: file size warning misleading
- **File:** `hooks/pre-commit-gate:37-44,52`
- **Fix:** Change message from "staged files exceed 200 lines" to "these files exceed 200 lines" (it checks total file size, not staged diff)

### I4. user-prompt-check: overly broad keywords
- **File:** `hooks/user-prompt-check:13`
- **Fix:** Remove generic words (fix, test, code, build, hook, service, component, module). Keep only compound patterns that clearly indicate dev work.

### I5. hooks.json: no timeout on sync hooks
- **File:** `hooks/hooks.json`
- **Fix:** Add `"timeout": 30000` to pre-commit-gate and session-start

### I6. researcher agent: WebSearch/WebFetch in tools
- **File:** `agents/researcher.md`
- **Fix:** Document MCP dependency or change to Bash-based web access

## Architectural Improvements (A1-A6)

### A1. bin/ directory with node wrapper
- Create `bin/node-check` that sources nvm and proxies to node/npx
- Automatically in PATH when plugin is enabled

### A2. Dynamic skill count in install.sh
- **File:** `scripts/install.sh:186-189`
- **Fix:** Count skills dynamically instead of hardcoded 46

### A3. plugin.json enhancements
- Add `repository`, `license`, `homepage` fields
- Reference hooks.json path explicitly

### A4. README update
- Add `claude --plugin-dir` dev instructions
- Add `/reload-plugins` workflow
- Document known env requirements (nvm, jq)

### A5. uninstall.sh: also clean installed_plugins.json
- Currently only cleans settings.json, leaves stale entry in installed_plugins.json

### A6. CHANGELOG.md for plugin
- Start tracking changes properly

## Execution Order

1. C1-C3: Fix path/key mismatches in uninstall.sh, update.sh (30 min)
2. C4 + A1: nvm sourcing in hooks + bin/ wrapper (1 hour)
3. I1-I5: Hook improvements (1 hour)
4. I6: Researcher agent docs (15 min)
5. A2-A3: install.sh + plugin.json improvements (30 min)
6. A4-A6: Documentation + CHANGELOG (1 hour)
7. Test via `claude --plugin-dir` in clean subdirectory
8. Code review via subagent
9. Merge to main, push

## Testing Strategy

- Create clean subdirectory in /home/bnskn/claudebot/
- Run install.sh in isolated environment
- Verify: skills count, agents count, hooks fire
- Verify: uninstall.sh cleans everything
- Verify: update.sh pulls latest
