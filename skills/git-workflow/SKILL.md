---
name: git-workflow
description: Branching strategy, conventional commits, and PR workflow for all development work
---

# Git Workflow

## Overview

Standardized git practices for all development work. Covers branching, commits, and pull requests.

**Core principle:** Code, test, verify, THEN commit once. Never commit untested code.

## Branching Strategy

### Feature Branches from Main

1. All work happens on feature branches off `main`
2. Branch naming: `<type>/<short-description>`
   - `feat/user-auth`
   - `fix/null-pointer-crash`
   - `refactor/split-large-module`
   - `docs/api-reference`
   - `test/integration-coverage`
3. NEVER commit directly to `main` or `master`
4. One feature per branch — do not bundle unrelated changes

### Branch Lifecycle

```
main ─────────────────────────────────────── main
       \                                   /
        feat/user-auth ── commits ── PR ──
```

1. Create branch: `git checkout -b feat/my-feature main`
2. Do all work on the branch
3. Open PR when ready
4. Merge via PR (squash or merge commit per project convention)
5. Delete branch after merge

## Conventional Commits

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | When to Use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests only |
| `docs` | Documentation only changes |
| `chore` | Build process, tooling, dependencies |
| `perf` | Performance improvement |
| `ci` | CI/CD configuration changes |

### Rules

1. **Description MUST be lowercase** — `feat: add user auth` not `feat: Add User Auth`
2. **Description MUST be imperative mood** — "add" not "added" or "adds"
3. **Scope is optional but encouraged** — `feat(auth): add login endpoint`
4. **Body explains WHY, not WHAT** — the diff shows what changed
5. **Keep subject line under 72 characters**
6. **One logical change per commit** — do not bundle unrelated work

### Examples

```
feat(auth): add JWT token refresh endpoint

Users with expired tokens had to re-login. This adds automatic
refresh when the access token expires within 5 minutes.

fix(parser): handle empty input without crashing

Closes #42

refactor(api): extract validation into middleware

```

## The Correct Commit Pattern

### Anti-Pattern (NEVER do this)

```
code something → commit → run tests → find bug → commit fix → repeat
```

This creates a messy history full of "fix typo" and "actually fix the bug" commits. It also means broken code exists in the commit history.

### Correct Pattern (ALWAYS do this)

```
1. Write code
2. Run tests
3. Fix any failures
4. Run tests again
5. All green? → commit once
```

**The rule:** NEVER commit code you have not tested. A commit represents a verified, working state.

### Checklist Before Every Commit

1. [ ] Code compiles/loads without errors
2. [ ] All existing tests still pass
3. [ ] New tests written and passing
4. [ ] No debugging artifacts left (console.log, print statements, TODO hacks)
5. [ ] Changes are scoped to one logical unit
6. [ ] Commit message follows conventional format

## PR Workflow

### Creating a PR

```bash
# Push branch
git push -u origin feat/my-feature

# Create PR with gh CLI
gh pr create --title "feat(auth): add JWT refresh" --body "$(cat <<'EOF'
## Summary
- Added token refresh endpoint
- Tokens auto-refresh when expiring within 5 minutes
- Added integration tests for refresh flow

## Test Plan
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual test: expired token triggers refresh
- [ ] Manual test: valid token skips refresh
EOF
)"
```

### PR Checklist

1. [ ] Branch is up to date with main (`git rebase main` or `git merge main`)
2. [ ] All tests pass on the branch
3. [ ] PR title follows conventional commit format
4. [ ] PR body includes Summary and Test Plan
5. [ ] No unrelated changes included
6. [ ] Reviewed own diff before requesting review

### Reviewing PRs

```bash
# Check out PR locally
gh pr checkout 123

# View PR diff
gh pr diff 123

# Approve
gh pr review 123 --approve

# Request changes
gh pr review 123 --request-changes --body "Issues found: ..."
```

### Merging

```bash
# Squash merge (clean history)
gh pr merge 123 --squash

# Merge commit (preserve branch history)
gh pr merge 123 --merge

# Delete branch after merge
gh pr merge 123 --squash --delete-branch
```

## Red Flags

**NEVER:**
- Commit directly to main/master
- Commit code that does not compile
- Commit code with failing tests
- Write "fix" commits for code in the same PR — fix it before committing
- Force-push to shared branches without coordination
- Bundle unrelated changes in one commit or PR

**ALWAYS:**
- Create feature branches for all work
- Test before committing
- Use conventional commit format
- Keep PRs focused on one feature/fix
- Update branch with main before merging
- Delete branches after merge
