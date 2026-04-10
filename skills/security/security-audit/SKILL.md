---
name: security-audit
description: Security audit checklist covering OWASP Top 10, prompt injection protection, input validation, and auth/authz review. Dispatches to security-auditor agent for deep analysis.
sub-team: security
type: rigid
---

# Security Audit

## When to Apply

Use this skill before deployment, when handling secrets or user data, and during security-focused code reviews. This skill is rigid -- all checklist items MUST pass before approval.

## OWASP Top 10 Checklist

### 1. Injection (SQL, NoSQL, OS, LDAP)

1. [ ] All database queries use parameterized statements or prepared queries
2. [ ] NEVER concatenate user input into SQL strings
3. [ ] ORM queries are reviewed for raw query escape hatches
4. [ ] OS command execution avoids user-controlled input (if unavoidable, use allowlists)

### 2. Broken Authentication

1. [ ] Passwords are hashed with bcrypt, scrypt, or argon2 (NEVER MD5, SHA-1, or plain SHA-256)
2. [ ] Session tokens are cryptographically random and sufficiently long (>=128 bits)
3. [ ] Session expiration is enforced (idle timeout + absolute timeout)
4. [ ] Multi-factor authentication is available for sensitive operations
5. [ ] Failed login attempts are rate-limited

### 3. Sensitive Data Exposure

1. [ ] All data in transit uses TLS 1.2+ (NEVER plain HTTP for sensitive data)
2. [ ] Sensitive data at rest is encrypted
3. [ ] API responses do not leak internal details (stack traces, DB schemas)
4. [ ] Logs do not contain passwords, tokens, or PII

### 4. XML External Entities (XXE)

1. [ ] XML parsers disable external entity processing
2. [ ] Prefer JSON over XML where possible

### 5. Broken Access Control

1. [ ] Every endpoint checks authorization (not just authentication)
2. [ ] Default deny -- access is explicitly granted, not implicitly allowed
3. [ ] CORS is configured to allow only trusted origins
4. [ ] Directory listing is disabled on web servers

### 6. Security Misconfiguration

1. [ ] Default credentials are changed
2. [ ] Debug mode is disabled in production
3. [ ] Security headers are set: CSP, X-Frame-Options, X-Content-Type-Options
4. [ ] Error pages do not reveal stack traces or server details

### 7. Cross-Site Scripting (XSS)

1. [ ] All user input is escaped before rendering in HTML
2. [ ] Content Security Policy (CSP) is configured
3. [ ] Framework auto-escaping is enabled (React JSX, template engines)
4. [ ] NEVER use `dangerouslySetInnerHTML` or equivalent without sanitization

### 8. Insecure Deserialization

1. [ ] NEVER deserialize untrusted data without validation
2. [ ] Use safe serialization formats (JSON, not Java serialization)
3. [ ] Validate deserialized object structure with schemas (Zod, JSON Schema)

### 9. Using Components with Known Vulnerabilities

1. [ ] `npm audit` / `pip audit` shows no critical or high vulnerabilities
2. [ ] Dependencies are pinned to specific versions (lockfile committed)
3. [ ] Automated vulnerability scanning is configured in CI

### 10. Insufficient Logging & Monitoring

1. [ ] Security events are logged (failed logins, access denied, input validation failures)
2. [ ] Logs are stored securely and cannot be tampered with
3. [ ] Alerting is configured for suspicious patterns

## Prompt Injection Protection

1. [ ] User input is NEVER concatenated directly into LLM prompts
2. [ ] System prompts and user messages are clearly separated
3. [ ] Input is sanitized before passing to LLM (strip control characters, limit length)
4. [ ] Output from LLM is validated before executing any actions
5. [ ] NEVER allow LLM output to directly execute system commands

## Input Validation at System Boundaries

1. [ ] All external input is validated at the entry point (API, CLI, file upload)
2. [ ] Validation rejects invalid input early -- fail fast
3. [ ] File uploads are restricted by type, size, and scanned for malware
4. [ ] NEVER trust client-side validation alone -- always validate server-side

## Auth/Authz Review

1. [ ] Authentication verifies identity (who you are)
2. [ ] Authorization verifies permissions (what you can do)
3. [ ] Principle of least privilege -- grant minimum required permissions
4. [ ] Token-based auth uses short-lived tokens with refresh mechanism
5. [ ] API keys are scoped to specific operations and rate-limited
6. [ ] Service-to-service auth uses mutual TLS or signed tokens

## Dispatch to Security-Auditor Agent

For deep analysis beyond this checklist, dispatch to the security-auditor agent with:

1. List of files touching authentication, authorization, or user input
2. Summary of external service integrations
3. Inventory of environment variables and secrets
4. Known areas of concern

**Expected agent output:**
```
Status: secure | vulnerabilities-found
### Critical Vulnerabilities (must fix)
### Medium Risk Issues
### Low Risk / Hardening Suggestions
### Secrets Check (exposed? rotated? gitignored?)
### Questions
### Notes
```

## Red Flags

- SQL concatenation with user input -- immediate injection risk
- Passwords stored in plain text or weak hash -- critical vulnerability
- No authorization checks on endpoints -- broken access control
- User input directly in LLM prompts -- prompt injection vector
- Debug mode enabled in production -- information disclosure
- No `npm audit` in CI -- unknown vulnerability exposure
