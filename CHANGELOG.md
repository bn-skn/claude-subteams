# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

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
