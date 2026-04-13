---
name: conventions-enforcer
description: Validates project structure against CONVENTIONS.md. Checks file sizes, import directions, and naming conventions. Generates compliance reports and provides templates for new projects.
---

# Conventions Enforcer

## When to Apply

Use this skill on project setup, during architecture reviews, and before merging structural changes. This skill is rigid -- all validation rules MUST pass before approval.

## CONVENTIONS.md Requirement

1. Every project MUST have a CONVENTIONS.md in the project root
2. If missing, generate one using the template from `templates/CONVENTIONS.md`
3. CONVENTIONS.md MUST contain numbered rules covering: layers, file limits, naming, testing
4. NEVER modify CONVENTIONS.md without explicit user consent

## Validation Checklist

### Structure Validation

1. [ ] CONVENTIONS.md exists in project root
2. [ ] All directories match the declared layer structure
3. [ ] No orphan files outside the defined structure
4. [ ] README.md or equivalent documentation exists

### File Size Validation

1. [ ] No file exceeds 200 lines (flag all violations with file path and line count)
2. [ ] No function exceeds 30 lines
3. [ ] Flag files between 150-200 lines as warnings (approaching limit)

### Import Direction Validation

Use grep-based checks to detect violations:

```bash
# Domain must not import from other layers
grep -rn "from.*infrastructure\|from.*presentation\|from.*application" src/domain/

# Application must not import from infrastructure or presentation
grep -rn "from.*infrastructure\|from.*presentation" src/application/

# Flag any circular imports
npx madge --circular src/
```

1. [ ] Domain imports nothing from other layers
2. [ ] Application imports only from domain
3. [ ] No circular dependencies detected
4. [ ] Cross-layer imports use interfaces, not concrete implementations

### Naming Convention Validation

```bash
# Check for non-kebab-case files
find src/ -name "*.ts" -o -name "*.js" | grep -v node_modules | grep '[A-Z]'

# Check for barrel files outside layer boundaries
find src/ -name "index.ts" -not -path "*/domain/index.ts" -not -path "*/application/index.ts" -not -path "*/infrastructure/index.ts" -not -path "*/presentation/index.ts"
```

1. [ ] All file names are kebab-case
2. [ ] Classes use PascalCase
3. [ ] Functions use camelCase
4. [ ] Constants use SCREAMING_SNAKE_CASE
5. [ ] No `I` prefix on interfaces

### Test Colocation Validation

1. [ ] Every `.ts` file has a corresponding `.test.ts` in the same directory
2. [ ] No top-level `test/` or `__tests__/` directory exists
3. [ ] Test coverage meets project minimum (if defined in CONVENTIONS.md)

## Compliance Report Format

Generate a report in this format:

```
## Conventions Compliance Report
Date: YYYY-MM-DD
Project: <project-name>

### Summary
- Total rules checked: N
- Passing: N
- Violations: N
- Warnings: N

### Violations (MUST fix)
1. [FILE_SIZE] src/domain/user.ts: 247 lines (max 200)
2. [IMPORT] src/domain/user.ts:15: imports from infrastructure/

### Warnings (SHOULD fix)
1. [FILE_SIZE] src/application/create-order.ts: 185 lines (approaching 200 limit)

### Passing
- All naming conventions followed
- Test colocation verified
```

## Template CONVENTIONS.md

When generating a new CONVENTIONS.md, include these sections:

1. Layer structure and allowed dependencies
2. File and function size limits
3. Naming conventions (files, classes, functions, constants)
4. Test strategy and colocation rules
5. Import rules and restrictions
6. CI enforcement tools

Reference the template at `templates/CONVENTIONS.md` for the full starting point.

## Red Flags

- Project has no CONVENTIONS.md -- generate one immediately
- Multiple files over 200 lines -- structural debt accumulating
- Domain importing infrastructure -- architectural violation, fix before proceeding
- Tests in separate directory tree -- restructure to colocate
- Inconsistent naming -- pick one convention and enforce everywhere
