---
name: ui-testing
description: "Browser-based UI testing with Playwright CLI. Dispatches ui-tester agent for visual verification, interaction testing, and CI-ready E2E test generation."
---

# UI Testing

## 1. Dispatch Protocol

1. This skill dispatches to the **ui-tester** agent for browser-based testing.
2. Agent model: sonnet (token-efficient for screenshot-heavy work).
3. Agent tools: Read, Write, Edit, Bash, Grep, Glob.
4. The agent uses Playwright CLI via Bash — NOT Playwright MCP.
5. ALWAYS provide: base URL, pages to test, expected behavior, design tokens path (if visual testing).

## 2. When to Use

| Scenario | Use This Skill |
|----------|---------------|
| After implementing a UI feature | Yes — verify it works in browser |
| Visual regression check before merge | Yes — screenshot comparison |
| Testing form flows and interactions | Yes — click, fill, submit |
| Generating E2E tests for CI | Yes — write .spec.ts files |
| Unit testing pure functions | No — use test-engineer instead |
| API endpoint testing | No — use test-engineer instead |

## 3. Testing Levels

### Quick Check (ad-hoc)
For fast verification during development:
1. Start dev server if not running.
2. Dispatch ui-tester with specific pages and viewports.
3. Review screenshots and test output.
4. No test files saved — one-off verification.

### Standard Testing (feature work)
For feature branches and PRs:
1. Write `.spec.ts` test files covering critical user flows.
2. Run at 3 viewports: 320px (mobile), 768px (tablet), 1280px (desktop).
3. Generate screenshot baselines for visual regression.
4. Verify all tests pass before merge.

### Full E2E Suite (CI pipeline)
For GitHub Actions integration:
1. All Standard tests plus cross-browser (Chromium + Firefox).
2. Visual regression against committed baselines.
3. Accessibility checks (axe-core via Playwright).
4. Performance metrics (LCP, CLS, FID).
5. Test results and screenshots as CI artifacts.

## 4. CI Integration Template

The ui-tester agent can generate this GitHub Actions workflow:

```yaml
# .github/workflows/e2e.yml
name: E2E Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: npm ci
      - run: npx playwright install --with-deps chromium
      - run: npm run build
      - run: npx playwright test
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: test-results/
          retention-days: 7
```

## 5. Brief Template for ui-tester

When dispatching the ui-tester agent, include:

```
Task: [what to test]
Base URL: [http://localhost:XXXX or deployed URL]
Pages: [list of routes to test]
Key flows: [user journeys to verify]
Design tokens: [path to tokens.json or tailwind.config.ts]
Viewports: [320, 768, 1280] (default) or custom
Mode: [quick-check | standard | full-e2e]
Expected: [what "working correctly" looks like]
```

## 6. Token Budget Guidelines

UI testing can be expensive. Control costs:

| Action | Token Cost | Rule |
|--------|-----------|------|
| Screenshot (take) | Low | Save to file, don't read |
| Screenshot (read/analyze) | High | Only when verifying specific visual issue |
| DOM inspection | Very High | NEVER read full DOM — use targeted selectors |
| Test file writing | Low | Write once, run many times |
| Test execution | Low | Playwright runs in Bash, minimal output |

**Target:** ui-tester session should use < 50k tokens for standard testing of 5-10 pages.

## 7. Critical Rules

1. NEVER use Playwright MCP for routine testing. CLI via Bash only.
2. ALWAYS test at minimum 2 viewports (mobile + desktop).
3. MUST save screenshots to files — never inline in agent output unless explicitly asked.
4. MUST generate CI-ready test files for any feature that has UI.
5. Test files MUST use Playwright's built-in waiting — no arbitrary `sleep()` or `waitForTimeout()`.
6. Visual regression baselines MUST be committed to the repo.
