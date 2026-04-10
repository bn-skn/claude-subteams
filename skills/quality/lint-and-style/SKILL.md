---
name: lint-and-style
description: Enforce consistent code style and quality through linters, formatters, and editor configuration. Covers ESLint, Prettier, EditorConfig, and language-specific tooling.
requires: []
conflicts-with: []
type: flexible
---

# Lint and Style

## Overview

Style consistency is not about preferences. It is about reducing cognitive load and preventing entire categories of bugs.

**Core principle:** Automate every style rule. If a human is arguing about formatting, the tooling is misconfigured.

## When to Invoke

**ALWAYS for:**
- New project setup
- Adding a new language or framework to an existing project
- Resolving style-related merge conflicts
- Onboarding a new tool (linter, formatter, editor config)

**NEVER for:**
- Overriding project-established style without team consensus
- Changing style mid-feature (finish the feature first)

## Configuration Hierarchy

```
1. EditorConfig     → Cross-editor basics (indent, line endings, charset)
2. Formatter        → Opinionated formatting (Prettier, Black, gofmt)
3. Linter           → Code quality rules (ESLint, pylint, golint)
4. Type Checker     → Static analysis (tsc, mypy, pyright)
```

Each layer builds on the previous. NEVER skip layers.

## Language-Specific Tooling

### TypeScript / JavaScript

| Tool | Purpose | Config File |
|------|---------|-------------|
| ESLint | Code quality, bug detection | `.eslintrc.*` or `eslint.config.*` |
| Prettier | Opinionated formatting | `.prettierrc` |
| EditorConfig | Editor-level defaults | `.editorconfig` |

**Setup checklist:**
1. Install ESLint with TypeScript parser
2. Install Prettier and `eslint-config-prettier` (disables conflicting rules)
3. Configure `lint-staged` with `husky` for pre-commit hooks
4. Add lint and format scripts to `package.json`
5. Verify: `npx eslint . && npx prettier --check .`

### Python

| Tool | Purpose | Config File |
|------|---------|-------------|
| Ruff or pylint | Linting | `pyproject.toml` or `.pylintrc` |
| Black or Ruff format | Formatting | `pyproject.toml` |
| isort or Ruff | Import sorting | `pyproject.toml` |
| mypy or pyright | Type checking | `pyproject.toml` or `pyrightconfig.json` |

### Go

| Tool | Purpose | Config File |
|------|---------|-------------|
| gofmt | Formatting (built-in) | None (standard) |
| golangci-lint | Linting (aggregator) | `.golangci.yml` |
| go vet | Static analysis (built-in) | None |

### Rust

| Tool | Purpose | Config File |
|------|---------|-------------|
| rustfmt | Formatting | `rustfmt.toml` |
| clippy | Linting | `clippy.toml` |

## EditorConfig Baseline

EVERY project MUST have an `.editorconfig` file:

```ini
root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{py,rs,go,java}]
indent_size = 4

[Makefile]
indent_style = tab
```

## Enforcement Rules

1. **Formatters MUST run on save** — configure the editor or pre-commit hook
2. **Linters MUST run in CI** — failing lint blocks merge
3. **NEVER disable a lint rule inline** without a comment explaining why
4. **NEVER use `eslint-disable` on an entire file** — fix the violations or exclude the file in config
5. **New code MUST pass all lint rules** — no grandfathering without explicit tech debt tracking
6. **Format the changed files only** — do not reformat the entire codebase in a feature PR

## Pre-Commit Hook Setup

```json
{
  "husky": { "hooks": { "pre-commit": "lint-staged" } },
  "lint-staged": {
    "*.{ts,tsx,js,jsx}": ["eslint --fix", "prettier --write"],
    "*.py": ["ruff check --fix", "ruff format"],
    "*.go": ["gofmt -w"]
  }
}
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Prettier and ESLint conflict | Install `eslint-config-prettier` |
| Linting entire codebase on every commit | Use `lint-staged` to lint only changed files |
| Different indent styles across editors | Add `.editorconfig` |
| Ignoring linter in CI | Add lint step to CI pipeline before tests |
| Disabling rules instead of fixing code | Fix the code; disable only with justification |

## The Bottom Line

Configure once. Automate everything. Argue about style zero times.

If the team is debating formatting, the formatter is not configured. If linting is optional, bugs will ship.
