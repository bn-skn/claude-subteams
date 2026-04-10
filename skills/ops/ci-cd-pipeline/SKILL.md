---
name: ci-cd-pipeline
description: Use when setting up or modifying CI/CD pipelines, deployment workflows, or environment promotion strategies
type: flexible
---

# CI/CD Pipeline

## Overview

Continuous integration and delivery pipelines automate the path from code to production. A well-designed pipeline catches issues early and deploys reliably.

**Core principle:** Every change MUST pass through lint, build, test, and deploy stages before reaching production.

## When to Use

- Setting up GitHub Actions or GitLab CI from scratch
- Adding or modifying pipeline stages
- Configuring environment promotion (dev, staging, production)
- Implementing automated rollback
- Setting up deployment notifications

## Pipeline Stages

ALWAYS follow this stage ordering. NEVER skip stages.

### 1. Lint Stage
- Run linters (ESLint, Prettier, Ruff, etc.) before anything else
- Fail fast on formatting and static analysis issues
- MUST run on every push and pull request

### 2. Build Stage
- Compile, bundle, or package the application
- Generate build artifacts and store them for downstream stages
- MUST NOT proceed if build fails

### 3. Test Stage
- Run unit tests, integration tests, and e2e tests
- Generate and publish test coverage reports
- MUST achieve minimum coverage thresholds before proceeding

### 4. Deploy Stage
- Deploy to the target environment based on branch or tag
- ALWAYS deploy to dev first, then staging, then production
- NEVER deploy directly to production from a feature branch

## Environment Promotion

### Checklist for Environment Configuration
1. Define environment-specific variables in CI secrets, NEVER in code
2. Use environment protection rules for staging and production
3. Require manual approval for production deployments
4. Tag releases with semantic versioning before production deploy
5. Verify health checks pass after each environment deployment

### Promotion Flow
```
dev (auto on merge to main)
  → staging (auto after dev health check passes)
    → production (manual approval required)
```

## Automated Rollback

### When Rollback Triggers
1. Health check endpoint returns non-200 after deploy
2. Error rate exceeds threshold within monitoring window
3. Deployment timeout exceeded

### Rollback Checklist
1. Detect failure via health check or monitoring alert
2. Revert to the last known-good deployment artifact
3. Run health checks against rolled-back version
4. Send notification to the team with failure details
5. Create an incident ticket for investigation

## Deployment Notifications

### MUST Notify On
1. Successful deployment to any environment
2. Failed deployment with error summary
3. Rollback triggered with reason
4. Manual approval requested for production

### Notification Channels
1. Slack or Teams webhook for real-time alerts
2. Email for deployment summaries
3. GitHub/GitLab comments on the triggering PR or commit

## GitHub Actions Template

```yaml
name: CI/CD Pipeline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint
        run: npm run lint

  build:
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: npm run build

  test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Test
        run: npm test

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to dev
        run: ./scripts/deploy.sh dev
```

## Critical Rules

- NEVER store secrets in pipeline configuration files
- NEVER skip the test stage, even for "urgent" hotfixes
- ALWAYS use pinned versions for CI actions and dependencies
- ALWAYS run pipelines in isolated, ephemeral environments
- MUST have rollback capability before enabling auto-deploy to production

## Quick Reference

| Stage | Purpose | Failure Action |
|-------|---------|----------------|
| Lint | Code quality | Block merge |
| Build | Compilation | Block pipeline |
| Test | Correctness | Block deploy |
| Deploy | Delivery | Rollback |
