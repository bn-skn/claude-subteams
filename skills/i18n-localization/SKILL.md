---
name: i18n-localization
description: Use when implementing internationalization, translation workflows, or locale-specific formatting
---

# Internationalization and Localization

## Overview

i18n is not an afterthought. Retrofitting localization into an existing codebase is 5-10x more expensive than building it in from the start.

**Core principle:** NEVER hardcode user-facing strings. ALWAYS externalize text from day one, even if you only support one language.

## When to Use

- Starting a new project that may need multiple languages
- Adding localization to an existing application
- Setting up translation file structure and workflows
- Implementing date, time, number, or currency formatting
- Adding right-to-left (RTL) language support

## Library Selection

### Recommended Libraries
| Platform | Library | Notes |
|----------|---------|-------|
| React/Next.js | i18next + react-i18next | Most mature, large ecosystem |
| Vue | vue-i18n | Official Vue integration |
| Angular | @angular/localize | Built-in framework support |
| Node.js | i18next | Same library, server-side |
| Mobile (RN) | i18next + react-i18next | Cross-platform consistency |
| Mobile (Flutter) | intl + flutter_localizations | Dart-native solution |

### Setup Checklist
1. Install chosen i18n library and required plugins
2. Configure default locale and fallback locale
3. Set up locale detection (browser, user preference, URL)
4. Initialize library before first render
5. MUST configure fallback behavior for missing translations
6. NEVER show raw translation keys to users

## Translation File Organization

### File Structure
```
locales/
  en/
    common.json       # Shared strings (buttons, labels, errors)
    auth.json         # Authentication-related strings
    dashboard.json    # Dashboard-specific strings
  es/
    common.json
    auth.json
    dashboard.json
  ar/
    common.json
    auth.json
    dashboard.json
```

### Organization Rules
1. Split translations by feature/page, not by component
2. Use namespaces to avoid key collisions across features
3. Keep keys descriptive and hierarchical: `auth.login.submitButton`
4. NEVER use the English text as the key (keys must be stable identifiers)
5. ALWAYS include a description/context field for translators
6. MUST keep all locale files in sync (same keys in every language)

### Key Naming Convention
```json
{
  "auth": {
    "login": {
      "title": "Sign In",
      "emailLabel": "Email Address",
      "passwordLabel": "Password",
      "submitButton": "Sign In",
      "errorInvalidCredentials": "Invalid email or password"
    }
  }
}
```

## Date, Time, and Currency Formatting

### Formatting Checklist
1. ALWAYS use `Intl.DateTimeFormat`, `Intl.NumberFormat`, or equivalent locale-aware APIs
2. NEVER manually format dates with string concatenation
3. Store all timestamps in UTC; convert to local time only at display
4. Use ISO 8601 for date serialization in APIs
5. MUST handle timezone differences correctly
6. ALWAYS display currency with the correct symbol and decimal format for the locale

### Common Patterns
```typescript
// Date formatting
new Intl.DateTimeFormat('de-DE', {
  year: 'numeric', month: 'long', day: 'numeric'
}).format(date); // "15. Januar 2026"

// Currency formatting
new Intl.NumberFormat('ja-JP', {
  style: 'currency', currency: 'JPY'
}).format(1500); // "¥1,500"
```

## Pluralization

### Rules
1. NEVER use simple if/else for plurals (languages have complex plural rules)
2. Use the i18n library's built-in pluralization (ICU MessageFormat or equivalent)
3. MUST support all plural forms required by target languages (some have 6 forms)
4. Test pluralization with values 0, 1, 2, 5, 21 at minimum

### ICU MessageFormat Example
```json
{
  "itemCount": "{count, plural, =0 {No items} one {# item} other {# items}}"
}
```

## RTL Language Support

### Implementation Checklist
1. Use logical CSS properties (`margin-inline-start` not `margin-left`)
2. Set `dir="rtl"` on the HTML element when RTL locale is active
3. Mirror layout direction: navigation, reading flow, icons with direction
4. MUST test with actual RTL content, not just flipped English
5. NEVER mirror universal icons (play button, checkmark, clock)
6. ALWAYS test text alignment, overflow, and truncation in RTL mode

### CSS Approach
```css
/* Use logical properties */
.card {
  margin-inline-start: 1rem;  /* Not margin-left */
  padding-inline-end: 0.5rem; /* Not padding-right */
  text-align: start;          /* Not text-align: left */
}
```

## Translation Workflow

### Process Checklist
1. Developers add new keys to the default locale file with context comments
2. Extract new/changed keys for translator review
3. Send translation batch to translators with context and screenshots
4. Import completed translations and validate format
5. Run automated checks: missing keys, untranslated strings, format errors
6. QA review in-context (not just string review)
7. MUST have a process for updating translations when source strings change
8. NEVER machine-translate and ship without human review for production

### Automated Checks
1. All keys present in all locale files (no missing translations)
2. No unused keys in locale files (remove dead translations)
3. Interpolation variables match across locales
4. No HTML in translation strings (use components for formatting)
5. Maximum string length respected (important for UI constraints)

## Critical Rules

- NEVER hardcode user-facing strings in source code
- NEVER use string concatenation to build translated sentences
- ALWAYS provide context for translators (comments, screenshots)
- MUST support fallback locale for missing translations
- MUST validate translation files in CI
- NEVER assume left-to-right text direction

## Quick Reference

| Area | Key Activities | Validation |
|------|---------------|------------|
| Setup | Library, locale detection, fallback | App renders in default locale |
| Strings | Externalize, namespace, key naming | No hardcoded strings in code |
| Formatting | Dates, numbers, currency via Intl API | Correct per locale |
| RTL | Logical CSS, dir attribute, layout mirroring | Tested with RTL content |
| Workflow | Extract, translate, import, validate | CI checks passing |
