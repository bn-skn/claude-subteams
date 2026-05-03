# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

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

