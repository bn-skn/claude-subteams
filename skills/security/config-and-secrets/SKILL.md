---
name: config-and-secrets
description: Manages environment configuration, secrets protection, .gitignore enforcement, rotation strategy, and protected file integrity for CLAUDE.md and SKILL.md.
sub-team: security
type: flexible
---

# Config and Secrets

## When to Apply

Use this skill when handling .env files, API keys, credentials, or environment-specific configuration. Also applies when reviewing .gitignore and protected file changes. Flexible -- adapt to the project's deployment model.

## Secrets Management Rules

1. Secrets MUST NEVER be committed to git -- no exceptions
2. NEVER hardcode secrets in source code (API keys, passwords, tokens, connection strings)
3. NEVER log secrets -- mask them in all log output
4. NEVER pass secrets as command-line arguments (visible in process listings)
5. ALWAYS load secrets from environment variables or a secrets manager

## .env Validation

1. Maintain a `.env.example` file listing all required variables (without values):

```bash
# .env.example
DATABASE_URL=
API_KEY=
JWT_SECRET=
REDIS_URL=
```

2. [ ] `.env.example` is committed to git and kept up to date
3. [ ] `.env` is in `.gitignore` (NEVER committed)
4. [ ] All variables in `.env.example` have corresponding values in `.env`
5. [ ] Application fails fast on startup if required variables are missing
6. Validate environment variables at application startup:

```typescript
const requiredEnvVars = ["DATABASE_URL", "API_KEY", "JWT_SECRET"];
for (const envVar of requiredEnvVars) {
  if (!process.env[envVar]) {
    throw new Error(`Missing required environment variable: ${envVar}`);
  }
}
```

## .gitignore Enforcement

The following patterns MUST be in `.gitignore`:

```gitignore
# Secrets and environment
.env
.env.local
.env.*.local
*.pem
*.key
*.p12

# Credentials
credentials.json
service-account.json
**/secrets/

# IDE and OS
.idea/
.vscode/settings.json
.DS_Store
```

1. [ ] `.gitignore` exists and includes all secret file patterns
2. [ ] No secret files are tracked by git (check with `git ls-files | grep -i secret\|\.env\|\.key\|\.pem`)
3. [ ] If a secret was accidentally committed, rotate it immediately -- removing from git history is not enough

## Environment-Specific Configuration

1. Use separate configuration for each environment:
   - `development` -- local defaults, verbose logging
   - `staging` -- production-like settings, test data
   - `production` -- secure settings, minimal logging
2. NEVER use production secrets in development or staging
3. Configuration precedence: environment variables > config files > defaults
4. NEVER conditionally skip security measures based on environment (`if (env !== 'production')`)

## Secret Rotation Strategy

1. [ ] API keys and tokens have defined rotation schedules
2. [ ] Rotation can be performed without downtime (support two active keys during transition)
3. [ ] Document rotation procedures for each secret type
4. [ ] Rotate immediately if a secret is exposed (committed to git, logged, shared)

Rotation schedule guidelines:
- **API keys:** Every 90 days
- **Database passwords:** Every 90 days
- **JWT signing keys:** Every 30 days
- **Service account tokens:** Every 180 days
- **After any incident:** Immediately

## Protected Files

The following files MUST only be edited with explicit user consent:

1. **CLAUDE.md** -- Project-level AI assistant configuration
2. **SKILL.md** -- Skill definitions for the plugin

Rules for protected files:
1. NEVER modify CLAUDE.md or SKILL.md without the user explicitly requesting the change
2. Before editing, confirm the intended change with the user
3. After editing, show the diff for user review
4. Protected file changes should be committed separately from code changes

## Secrets in CI/CD

1. Use the CI platform's secret management (GitHub Secrets, GitLab CI Variables)
2. NEVER echo or print secrets in CI logs
3. Mask secrets in CI output (`::add-mask::` in GitHub Actions)
4. Use short-lived tokens where possible (OIDC for cloud providers)
5. Limit secret access to the jobs and environments that need them

## Audit Checklist

1. [ ] No secrets in source code (search: `grep -rn "password\|api_key\|secret\|token" --include="*.ts" --include="*.js" --include="*.py" src/`)
2. [ ] `.env` is in `.gitignore`
3. [ ] `.env.example` exists and is current
4. [ ] Application validates required env vars at startup
5. [ ] No secrets in git history (check recent commits)
6. [ ] Rotation schedule is documented
7. [ ] Protected files (CLAUDE.md, SKILL.md) are unchanged or user-approved
8. [ ] CI secrets use platform-native secret management

## Red Flags

- Secret found in source code or git history -- rotate immediately
- `.env` file committed to git -- add to `.gitignore` and rotate all secrets in it
- No `.env.example` -- team members will not know what variables are needed
- Application starts without required env vars -- add startup validation
- Same secrets used across environments -- use separate secrets per environment
- Protected file modified without user consent -- revert and ask
