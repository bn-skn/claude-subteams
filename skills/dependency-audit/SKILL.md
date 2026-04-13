---
name: dependency-audit
description: Audits project dependencies for vulnerabilities, lockfile integrity, license compliance, and unused packages. Defines update strategy for patch, minor, and major versions.
sub-team: security
type: flexible
---

# Dependency Audit

## When to Apply

Use this skill periodically, when adding or updating dependencies, and before releases. Flexible -- adapt the depth of audit to the project's risk profile.

## Vulnerability Scanning

1. Run the appropriate scanner for your ecosystem:

```bash
# Node.js
npm audit --audit-level=high

# Python
pip audit

# Go
govulncheck ./...

# Rust
cargo audit
```

2. [ ] No critical or high vulnerabilities in production dependencies
3. [ ] Medium vulnerabilities reviewed and accepted or mitigated
4. [ ] Low vulnerabilities tracked for future resolution
5. NEVER ignore critical vulnerabilities -- fix or replace the dependency
6. If a vulnerability has no fix available, document the risk and add compensating controls

## Lockfile Integrity

1. [ ] Lockfile exists and is committed to version control (`package-lock.json`, `poetry.lock`, `go.sum`)
2. [ ] Lockfile is not manually edited -- only updated via package manager commands
3. [ ] CI installs from lockfile only (`npm ci`, not `npm install`)
4. [ ] Lockfile hash matches expected values (no tampering)
5. NEVER delete and regenerate the lockfile without reviewing all version changes

## License Compliance

1. [ ] All dependencies use licenses compatible with the project's license
2. [ ] No GPL-licensed dependencies in proprietary/commercial projects (unless intended)
3. [ ] License audit results are documented

Acceptable licenses for most commercial projects:
- MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, 0BSD

Requires legal review:
- LGPL, MPL-2.0

Incompatible with proprietary:
- GPL-2.0, GPL-3.0, AGPL-3.0

```bash
# Node.js license check
npx license-checker --summary --failOn "GPL-2.0;GPL-3.0;AGPL-3.0"
```

## Update Strategy

### Patch versions (x.x.PATCH) -- Auto-update

1. Security fixes and bug fixes only
2. Safe to auto-merge with passing tests
3. Configure Dependabot/Renovate to auto-merge patch updates

### Minor versions (x.MINOR.x) -- Review

1. New features, non-breaking changes
2. Review changelog before updating
3. Run full test suite after update
4. Merge manually after review

### Major versions (MAJOR.x.x) -- Plan

1. Breaking changes expected
2. Read migration guide thoroughly
3. Create a dedicated branch for the upgrade
4. Update incrementally -- do not jump multiple major versions at once
5. Document the upgrade in an ADR if it affects architecture

## Removing Unused Dependencies

1. Periodically scan for unused dependencies:

```bash
# Node.js
npx depcheck

# Python
pip-extra-reqs --ignore-module=tests .
```

2. [ ] No unused production dependencies
3. [ ] Dev dependencies are actually used in development/testing
4. Remove unused dependencies -- they increase attack surface and bundle size
5. NEVER keep a dependency "just in case" -- reinstall when actually needed

## Adding New Dependencies

Before adding a new dependency, evaluate:

1. [ ] Is the dependency actively maintained? (last commit < 6 months)
2. [ ] Does it have known vulnerabilities? (`npm audit` / `pip audit`)
3. [ ] Is the license compatible with the project?
4. [ ] How many transitive dependencies does it pull in?
5. [ ] Can the functionality be implemented in < 50 lines without the dependency?
6. [ ] Is there a lighter alternative?

## Audit Checklist

1. [ ] Vulnerability scan shows no critical/high issues
2. [ ] Lockfile is committed and not manually modified
3. [ ] All licenses are compatible with project license
4. [ ] No unused dependencies in production
5. [ ] Update strategy is followed (patch auto, minor review, major plan)
6. [ ] New dependencies evaluated before adding
7. [ ] Dependabot or Renovate is configured for automated updates

## Red Flags

- Critical vulnerability with available fix not applied -- update immediately
- No lockfile in version control -- add and commit it
- GPL dependency in proprietary project -- replace or get legal approval
- Dependency with no updates in 2+ years -- evaluate alternatives
- 100+ transitive dependencies from a single package -- find a lighter option
- `npm install` used in CI instead of `npm ci` -- switch to lockfile-only install
