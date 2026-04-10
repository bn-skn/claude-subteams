---
name: design-qa
description: "Design quality assurance: compare implementation against spec, run heuristic evaluation, check visual consistency and responsiveness."
sub-team: design
type: rigid
---

# Design QA

## 1. Dispatch Protocol

1. This skill dispatches to the design-critic agent for evaluation.
2. Agent model: opus.
3. Agent tools: Read, Grep, Glob, Bash.
4. Add Playwright tools if browser verification is needed.
5. ALWAYS provide the agent with: spec/requirements, file paths to implementation, design tokens file path.

## 2. Spec Comparison Checklist

1. Read the original spec or requirements document.
2. Read every implemented component file.
3. For each spec requirement, verify it exists in the implementation.
4. Record each requirement as: PASS, FAIL, or PARTIAL.
5. MUST flag any implementation that has NO corresponding spec requirement (scope creep).
6. MUST flag any spec requirement with NO implementation (missing feature).

## 3. Nielsen Norman Heuristics Evaluation

Run each heuristic against the implementation:

| # | Heuristic | Check |
|---|-----------|-------|
| 1 | Visibility of system status | Loading states, progress indicators, feedback on actions |
| 2 | Match between system and real world | Natural language, familiar icons, logical order |
| 3 | User control and freedom | Undo/redo, cancel buttons, easy navigation back |
| 4 | Consistency and standards | Same patterns for same actions, platform conventions |
| 5 | Error prevention | Confirmations for destructive actions, input validation |
| 6 | Recognition rather than recall | Visible options, contextual help, clear labels |
| 7 | Flexibility and efficiency | Keyboard shortcuts, power-user paths, customization |
| 8 | Aesthetic and minimalist design | No unnecessary elements, clear visual hierarchy |
| 9 | Help users recognize and recover from errors | Clear error messages, suggested fixes |
| 10 | Help and documentation | Tooltips, onboarding, contextual help |

1. Rate each heuristic: PASS, WARN, or FAIL.
2. For WARN and FAIL, provide specific file:line references and recommended fix.
3. NEVER skip heuristics — evaluate all 10 even if some seem irrelevant.

## 4. Visual Consistency Check

1. Verify all colors come from design tokens — no hardcoded values.
2. Verify spacing follows the defined scale — no arbitrary pixel values.
3. Verify typography uses defined font families, sizes, and weights.
4. Check alignment: elements that should align vertically or horizontally do so.
5. Check visual hierarchy: most important elements are most prominent.
6. Verify consistent border radii and shadow usage.

## 5. Responsive Behavior Verification

1. Check layout at 320px (mobile), 768px (tablet), 1280px (desktop).
2. Verify no horizontal scrolling at any breakpoint.
3. Verify touch targets are at least 44x44px on mobile.
4. Verify text remains readable (minimum 16px body text on mobile).
5. Verify images and media scale correctly.
6. Check that navigation adapts appropriately (hamburger menu, etc.).

## 6. Screenshot Comparison (if Playwright available)

1. Navigate to each page/view in the implementation.
2. Capture screenshots at 320px, 768px, and 1280px widths.
3. Compare against spec mockups or reference screenshots if available.
4. Flag visual regressions: layout shifts, missing elements, broken styling.
5. Save screenshots for future regression comparisons.

## 7. Output Format

The design-critic agent MUST return results in this structure:

```
Status: approved | needs-work

### Spec Coverage
X/Y requirements implemented

### Heuristics Score
X/10 passing

### Design Issues
- [file:line] Heuristic violated. Impact. Suggested improvement.

### Accessibility Issues
- [file:line] WCAG criterion. Severity. Fix.

### Visual Issues
- [list of visual consistency problems]

### Responsive Issues
- [list of responsive behavior problems]

### Critical Fixes (must fix before shipping)
- [list]

### Recommended Fixes (should fix, not blocking)
- [list]
```

## 8. Critical Rules

1. NEVER approve a design that has FAIL on any Nielsen Norman heuristic without explicit user override.
2. NEVER skip responsive verification.
3. ALWAYS provide file:line references for every issue found.
4. MUST re-run QA after fixes are applied to confirm resolution.
