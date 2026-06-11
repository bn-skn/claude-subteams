# Backlog

## In Progress
- [x] Fire test on claudebot — real development task with plugin active

## Next Up
- [ ] Polish remaining 41 skills iteratively (prioritize by usage frequency)
- [ ] Replace claudebot CLAUDE.md methodology section (120 lines) with plugin snippet (6 lines)
- [ ] Enable subteams globally, disable superpowers
- [ ] Add CONVENTIONS.md to claudebot project

## Ideas
- **Architecture-doc tripwire at read time (follow-up to v1.18.0).** The arch-capture gate (Rule 24) only fires in the Full+Architecture pipeline. A greenfield "just do it" routes to Lightweight/Standard, skips brainstorming, and ships a stub `ARCHITECTURE.md` with no gate — then a later session's `architecture-guard` reads the unpopulated template as truth (deferred empty-truth). Consider: `architecture-guard` (or the session-start hook) flags when it is about to treat a stub arch doc (sentinel still present) as ground truth.
- Publish to Claude Code plugin marketplace (when stable)
- Add skill manifest to plugin.json for better discovery
- Merge overlapping skills (orchestrator-briefing + subagent-prompt-design + agent-engineering → one skill)
- Add metrics collection (bugs caught, review findings, tokens consumed)
- External reviewer integration (Codex, Gemini)
- Hookify integration — auto-generate hooks from plugin rules

## Done
- [x] Design specification (29 sections, 5 review rounds) — 2026-04-10
- [x] Implementation v1.0 (46 skills, 9 agents, 6 hooks) — 2026-04-10
- [x] 3 rounds QA review + fixes — 2026-04-10
- [x] Polish 5 key skills to professional quality — 2026-04-10
- [x] Full audit by fresh-eyes reviewer — 2026-04-11
- [x] Audit fixes (visual-companion, conventions, README activation) — 2026-04-11
- [x] Published to GitHub: github.com/bn-skn/claude-subteams — 2026-04-10

## Recurring
- [ ] On version bump: verify README.md, INSTALL.md, templates/claudemd-snippet.md reflect current agent count, version, and features
