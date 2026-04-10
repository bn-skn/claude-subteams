---
name: claudemd-engineering
description: "Standards for writing and maintaining CLAUDE.md files: concise, prioritized, and regularly pruned."
type: flexible
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
