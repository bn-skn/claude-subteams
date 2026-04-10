---
name: accessibility
description: "WCAG 2.1 AA compliance audit: semantic HTML, keyboard navigation, screen reader support, color contrast, and ARIA attributes."
type: flexible
---

# Accessibility Audit

## 1. Scope

1. This skill applies to any UI implementation: HTML, React, Vue, Svelte, or any component framework.
2. Target compliance: WCAG 2.1 Level AA.
3. Run this skill after implementation, before shipping.
4. Can be run standalone or as part of the design-qa pipeline.

## 2. Semantic HTML Checklist

1. Verify page has exactly one `<main>` element.
2. Verify heading hierarchy is sequential (`h1` then `h2` then `h3` — no skipping levels).
3. Verify exactly one `h1` per page.
4. Verify lists use `<ul>`, `<ol>`, or `<dl>` — not styled `<div>`s.
5. Verify navigation uses `<nav>` element.
6. Verify forms use `<form>`, `<fieldset>`, `<legend>`, and `<label>` elements.
7. Verify tables use `<table>`, `<thead>`, `<tbody>`, `<th>` with `scope` attribute.
8. Verify buttons are `<button>` elements, not clickable `<div>` or `<span>`.
9. Verify links are `<a>` elements with `href`, not clickable `<div>` or `<span>`.
10. NEVER use `<div>` or `<span>` with `onClick` for interactive elements.

## 3. Keyboard Navigation

1. Verify all interactive elements are focusable via Tab key.
2. Verify focus order matches visual reading order (left-to-right, top-to-bottom).
3. Verify visible focus indicators on all focusable elements — NEVER `outline: none` without replacement.
4. Verify Escape key closes modals, dropdowns, and popovers.
5. Verify Enter/Space activates buttons and links.
6. Verify arrow keys navigate within composite widgets (tabs, menus, radio groups).
7. Verify no keyboard traps — focus must always be escapable.
8. Verify skip-to-main-content link exists on pages with navigation.

## 4. Screen Reader Compatibility

1. All images MUST have `alt` text. Decorative images use `alt=""`.
2. All form inputs MUST have associated `<label>` elements (explicit `for`/`id` or wrapping).
3. All icon-only buttons MUST have `aria-label` or visually hidden text.
4. Dynamic content updates MUST use `aria-live` regions (`polite` for non-urgent, `assertive` for urgent).
5. Modals MUST have `role="dialog"` and `aria-labelledby` pointing to the modal title.
6. Custom widgets MUST use appropriate ARIA roles (e.g., `role="tablist"`, `role="tab"`, `role="tabpanel"`).
7. NEVER use `aria-label` on non-interactive elements unless they have a widget role.
8. Verify `aria-hidden="true"` is used on decorative/redundant elements.

## 5. Color Contrast

1. Normal text (below 18pt / 24px): minimum contrast ratio 4.5:1.
2. Large text (18pt+ / 24px+ or 14pt+ bold): minimum contrast ratio 3:1.
3. UI components and graphical objects: minimum contrast ratio 3:1 against adjacent colors.
4. NEVER rely on color alone to convey information — always pair with text, icons, or patterns.
5. Verify links are distinguishable from surrounding text (underline or 3:1 contrast + non-color indicator).
6. Check contrast in all states: default, hover, focus, active, disabled.

## 6. ARIA Attributes Audit

1. Verify no redundant ARIA (e.g., `role="button"` on `<button>` is redundant).
2. Verify all `aria-describedby` and `aria-labelledby` IDs point to existing elements.
3. Verify `aria-expanded` is used on toggles that show/hide content.
4. Verify `aria-current="page"` is used on the active navigation link.
5. Verify `aria-required="true"` is used on required form fields.
6. Verify `aria-invalid="true"` is set on fields with validation errors.
7. Verify `aria-disabled="true"` is used alongside visual disabled styling.

## 7. Additional Checks

1. Verify page has a meaningful `<title>`.
2. Verify `lang` attribute is set on `<html>` element.
3. Verify text can be resized to 200% without loss of content or functionality.
4. Verify animations respect `prefers-reduced-motion` media query.
5. Verify auto-playing media has pause/stop controls.
6. Verify touch targets are at least 44x44 CSS pixels.

## 8. Output Format

For each issue found, report:
- Severity: CRITICAL (blocks AA compliance), MODERATE (should fix), MINOR (best practice)
- WCAG criterion: e.g., "1.4.3 Contrast (Minimum)"
- File and line reference
- Current state and recommended fix

## 9. Red Flags Table

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| `outline: none` without replacement | Removes keyboard focus visibility | Provide custom focus indicator |
| `<div onClick={...}>` | Not keyboard accessible, no role | Use `<button>` element |
| Image without `alt` | Screen readers cannot describe it | Add descriptive `alt` or `alt=""` |
| Color-only status indicators | Invisible to colorblind users | Add icon, text, or pattern |
| `tabIndex > 0` | Breaks natural tab order | Use `tabIndex={0}` or DOM order |
