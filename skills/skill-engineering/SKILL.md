---
name: skill-engineering
description: "Standards for writing high-quality SKILL.md files: one job per skill, numbered checklists, critical rules, and mandatory testing."
---

# Skill Engineering

## 1. One Skill = One Job

1. Each skill MUST have exactly one clear responsibility.
2. If you cannot describe the skill's job in one sentence, it is too broad — split it.
3. NEVER combine unrelated concerns in a single skill (e.g., "testing and deployment").
4. The skill name MUST reflect the job (verb-noun or noun format).
5. If two skills overlap by more than 30%, merge them or clarify boundaries.

## 2. Structure Requirements

Every SKILL.md MUST contain:

1. **YAML frontmatter** with: `name`, `description` (one sentence), `type` (rigid or flexible).
2. **Numbered sections** using `## N. Section Title` format.
3. **Numbered checklists** within sections — not prose paragraphs.
4. **Red flags table** with columns: pattern, why it is wrong, correct action.
5. **Critical rules section** at the end with NEVER/ALWAYS/MUST statements.

## 3. Writing Rules

1. Use numbered lists, not bullet points.
2. Use NEVER for things that must not happen under any circumstances.
3. Use ALWAYS for things that must happen every time without exception.
4. Use MUST for requirements that are mandatory but may have rare exceptions.
5. Use SHOULD for recommendations that are best practice but not mandatory.
6. Keep each list item to one sentence. Two sentences maximum.
7. NEVER write prose paragraphs — convert to numbered steps.
8. NEVER use vague language ("try to", "consider", "might want to").
9. Use tables for reference data, decision matrices, and red flags.
10. Total length: 50-150 lines. Under 50 is too thin. Over 150 is too complex — split.

## 4. Frontmatter Specification

```yaml
---
name: kebab-case-name
description: "One sentence. Starts with verb or noun. Ends with period."
---
```

1. `name` MUST match the directory name.
2. `description` MUST be under 120 characters.
3. `type: rigid` — agent MUST follow every step in order. No skipping, no reordering.
4. `type: flexible` — agent follows the spirit but can adapt steps to context.

## 4a. Where a Rule Lives Decides Whether It Fires

Measured 2026-08-02 across two eval rounds (headless runs, `delivering-to-user` and `context-gaps`). Three layers, and only two of them are always present:

| Layer | In context | Use it for |
|-------|-----------|------------|
| The host's own instruction file | Always | Invariants that must hold on EVERY turn |
| Skill `description` | Always (all skills' metadata is resident) | The trigger, the antitrigger, and any one-line rule that must not be missed |
| Skill body | Only when the skill is invoked — measured ~40% on its own declared class | Depth: what exactly to check, how to judge, worked procedure |

1. The platform does NOT invoke a skill for work the model already performs unaided. Response formatting, tone, and length are that class — a skill carrying them fired on 2 of 5 in-class deliveries and was NOT reproducible on identical input.
2. Therefore: a rule whose violation is SILENT (no error, no failed test, just quietly worse output) must NOT live in the body alone.
3. Narrowing the description does not fix an undertriggering body. It was tried: rewriting the trigger from a broad phrase to concrete artifact nouns left the rate unchanged at 2/5.
4. Corollary for portability: when a skill is meant to carry methodology to another host, any invariant must be reproduced in the host's instruction template too. A pointer is not a rule.

## 5. Red Flags Table Format

Every skill MUST include a red flags table:

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| [Bad behavior] | [Concrete harm] | [Specific fix] |

1. Minimum 3 rows, maximum 8 rows.
2. NEVER use abstract harms ("it's bad practice"). State the concrete consequence.
3. Correct action MUST be actionable, not "be careful" or "think about it."

## 6. Testing Requirements

1. After writing a skill, create 5-10 representative test inputs.
2. Test inputs MUST cover: normal use (3), edge cases (2-3), misuse attempts (1-2).
3. Run each test and verify the skill produces correct behavior.
4. Save passing tests as regression tests.
5. NEVER ship a skill without testing it with at least 5 inputs.

## 7. Skill-Creator as Starting Point

1. Use the skill-creator tool to generate initial skill structure.
2. ALWAYS hand-edit the generated output. Skill-creator produces a draft, not a final product.
3. Remove generic boilerplate that does not apply to this specific skill.
4. Add domain-specific rules that skill-creator cannot know.
5. NEVER ship a skill-creator output without manual review and editing.

## 8. Review Checklist Before Shipping

1. Frontmatter is valid YAML with all required fields.
2. Name in frontmatter matches directory name.
3. Description is one sentence under 120 characters.
4. All sections use numbered checklists, not prose.
5. Red flags table exists with 3-8 rows.
6. Critical rules section exists with NEVER/ALWAYS/MUST statements.
7. Total length is 50-150 lines.
8. Tested with 5+ representative inputs.
9. No duplicate content with other existing skills.

## 9. Critical Rules

1. NEVER ship a skill without the review checklist (section 8) passing.
2. NEVER write prose paragraphs in a skill — always numbered lists.
3. ALWAYS include a red flags table.
4. MUST test with at least 5 representative inputs before shipping.
5. NEVER exceed 150 lines — split into two skills if needed.
6. ALWAYS hand-edit skill-creator output before shipping.
