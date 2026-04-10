---
name: design-to-code
description: "Pipeline from text spec to working code with design system, browser preview, and feedback loop. Code IS the mockup."
type: flexible
---

# Design-to-Code Pipeline

## 1. Stack Selection

1. Check project CONVENTIONS.md first — if stack is specified, use it.
2. If no CONVENTIONS.md or no stack specified, ask the user.
3. If user has no preference, suggest Tailwind CSS + shadcn/ui as default.
4. Vanilla CSS is ALWAYS a valid option — never dismiss it.
5. NEVER assume a framework. Confirm before writing any code.

## 2. Design Tokens

1. Create a single design tokens file before any component code.
2. Include at minimum: colors (primary, secondary, accent, neutral, error, success), spacing scale, typography (font families, sizes, weights, line heights), border radii, shadows.
3. Format depends on stack: CSS custom properties for vanilla, Tailwind config extension for Tailwind, theme object for CSS-in-JS.
4. NEVER hardcode color values, spacing, or font sizes in components — always reference tokens.
5. Name tokens semantically (e.g., `color-surface`, `color-on-surface`) not by appearance (e.g., NOT `color-light-gray`).

## 3. Component Inventory

1. Before coding, produce a flat list of every component needed.
2. Each entry MUST include: component name, props interface (typed), brief description.
3. Keep it flat — no nesting categories. One list, alphabetically sorted.
4. Identify shared components (buttons, inputs, cards) vs page-specific components.
5. Mark which components are interactive vs static.

## 4. Implementation Checklist

1. Set up project structure (tokens file, component directory, entry point).
2. Implement shared/base components first (buttons, inputs, typography).
3. Implement page-specific components, composing from base components.
4. Wire up layout and routing if applicable.
5. Add responsive breakpoints — mobile-first approach.
6. Add hover/focus/active states for all interactive elements.
7. Add loading and error states where applicable.

## 5. Browser Preview and Feedback Loop

1. After initial implementation, open in browser for visual verification.
2. Use Playwright screenshot if available to capture current state.
3. Compare against the original spec — check layout, spacing, colors, typography.
4. Iterate: identify gaps, fix, re-preview. Maximum 3 feedback rounds.
5. If Playwright is unavailable, describe the expected visual result and ask user to confirm.

## 6. Consistency Enforcement

1. Run linter/formatter after every implementation round.
2. Verify all components use design tokens — no magic numbers.
3. Check naming conventions are consistent across all components.
4. Verify prop interfaces match actual usage.
5. MUST ensure responsive behavior works at 320px, 768px, and 1280px minimum.

## 7. Red Flags Table

| Rationalization | Why It Is Wrong | Correct Action |
|-----------------|-----------------|----------------|
| "I'll pick the stack myself" | User may have strong preferences or constraints | Ask first, check CONVENTIONS.md |
| "Just one hardcoded color won't matter" | Hardcoded values multiply fast | Always use tokens |
| "Figma mockup first, then code" | Code IS the mockup in this pipeline | Skip Figma, build directly |
| "I'll make it responsive later" | Retrofitting responsiveness is 3x harder | Mobile-first from the start |
| "This component is too small to type" | Untyped props cause runtime bugs | Every component gets a props interface |
