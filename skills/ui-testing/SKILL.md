---
name: ui-testing
description: "Reference for browser UI checks: when to dispatch the ui-tester agent and what to put in its brief. The agent's procedure lives in agents/ui-tester.md; where the check sits in the pipeline lives in using-subteams §6.7."
---

# UI Testing

This skill is a reference, not a procedure. Two other places own the substance:

- **When the UI check runs, in what order, and what reaches the user** — `using-subteams` §6.7.
- **What the ui-tester does** (find suites → run the project's e2e → live review with screenshots at 320 and 1280 → improvements) — `agents/ui-tester.md`.

## 1. Dispatch

1. Agent: **ui-tester** (sonnet). Tools: Read, Write, Edit, Bash, Grep, Glob.
2. Suites run through `subteams-tests run`; the live review runs through `subteams-browser` (agent-browser, installs itself on first use; needs a system Chrome, or the user runs `subteams-browser setup`). No Playwright MCP.
3. The app is reached only through the project contract's `app` or a URL you put in the brief. Do not give the agent start commands.

## 2. When to Use

| Scenario | ui-tester? |
|----------|-----------|
| UI change above the small-change threshold (using-subteams §6.7) | Yes |
| New or changed user flow, form, or state | Yes — it may add an e2e test in the project's existing framework |
| Cosmetic change (color, spacing, copy) above the threshold | Yes — review and screenshots; no new test |
| Chaos / fuzz pass on an interface | Yes — `mode: monkey` |
| Unit testing pure functions, API endpoints | No — test-engineer |
| Docs, emails or pages excluded by the contract's `ui_exclude` | No |

## 3. Brief Template

```
Task: [what changed, in one line]
Base: [git ref the change is measured from; default HEAD]
Changed screens: [routes / views to review]
URL: [only if the project contract has no usable `app`]
Key flows: [user journeys to drive; or "see ## User Stories in <plan>"]
Mode: [scenario (default) | monkey]
Expected: [what "working correctly" looks like]
```

## 4. Token Budget

| Action | Token Cost | Rule |
|--------|-----------|------|
| Screenshot (take) | Low | Through `subteams-browser screenshot`, into the plugin cache — never the project |
| Screenshot (read) | High | Read each one once to judge it; report the path, do not inline |
| Element lookup | Low | `snapshot -i` and targeted selectors |
| Full DOM dump | Very High | Never |
| Suite run | Low | `subteams-tests run`, minimal output |

## 5. CI Workflow (only on request, only when the project already has Playwright Test)

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

## 6. Critical Rules

1. NEVER use Playwright MCP for the UI check.
2. Widths, screenshots, new-test rules and the defect/improvement line are the agent's — `agents/ui-tester.md`. Do not override them in a brief.
3. Nothing is installed into the project silently: no framework → the agent asks, you pass the question to the user.
