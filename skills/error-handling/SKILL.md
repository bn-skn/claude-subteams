---
name: error-handling
description: Resilient error handling patterns including retry with backoff, circuit breakers, graceful degradation, and structured error reporting. Fix root causes, not symptoms.
---

# Error Handling

## Overview

Every system fails. The question is whether it fails gracefully or catastrophically.

**Core principle:** Fix the root cause, not the symptom. A retry that hides a broken dependency is not error handling — it is error hiding.

## When to Invoke

**ALWAYS for:**
- Any code that calls external services (APIs, databases, file systems)
- Any user-facing operation that can fail
- Any background job or async operation
- Any operation involving money, data mutation, or security

**NEVER for:**
- Swallowing errors to make tests pass
- Catching exceptions just to log and re-throw identically
- Adding retry logic before understanding why something fails

## Error Handling Hierarchy

```
1. PREVENT  → Validate inputs before processing
2. HANDLE   → Catch specific errors, take appropriate action
3. RECOVER  → Retry, fallback, or degrade gracefully
4. REPORT   → Log structured context for debugging
5. ESCALATE → Alert humans when automated recovery fails
```

NEVER skip levels. Validate before you try. Handle before you retry. Report before you escalate.

## Retry with Exponential Backoff

**When to use:** Transient failures (network timeouts, rate limits, temporary unavailability).

**When NOT to use:** Permanent failures (auth errors, validation errors, 404s).

### Implementation Rules

1. Set a maximum retry count (typically 3-5)
2. Use exponential backoff: `delay = baseDelay * 2^attempt`
3. Add jitter to prevent thundering herd: `delay += random(0, delay * 0.1)`
4. ALWAYS set a maximum delay cap (e.g., 30 seconds)
5. NEVER retry non-idempotent operations without confirmation
6. Log each retry attempt with attempt number and delay

### Retryable vs Non-Retryable Errors

| Retryable | Non-Retryable |
|-----------|---------------|
| 429 Too Many Requests | 400 Bad Request |
| 500 Internal Server Error | 401 Unauthorized |
| 502 Bad Gateway | 403 Forbidden |
| 503 Service Unavailable | 404 Not Found |
| Connection timeout | 422 Validation Error |
| DNS resolution failure | Schema mismatch |

## Circuit Breaker

**When to use:** Repeated failures to an external service that is likely down.

### States

```
CLOSED  → Requests pass through normally
         → Track failure count
         → If failures >= threshold: move to OPEN

OPEN    → ALL requests fail immediately (no external call)
         → After timeout period: move to HALF-OPEN

HALF-OPEN → Allow ONE test request through
           → If success: move to CLOSED, reset counters
           → If failure: move to OPEN, reset timeout
```

### Configuration

| Parameter | Typical Value | Purpose |
|-----------|--------------|---------|
| Failure threshold | 5 failures | Trips the breaker |
| Timeout period | 30-60 seconds | Time before retry |
| Success threshold | 1-3 successes | Confirms recovery |

## Graceful Degradation

When a dependency fails, the system MUST NOT crash. Instead:

1. **Serve cached data** — stale data is better than no data
2. **Disable the feature** — hide the UI element, skip the step
3. **Provide a fallback** — default value, alternative service
4. **Inform the user** — "This feature is temporarily unavailable"

### Degradation Checklist

- [ ] Every external dependency has a defined fallback behavior
- [ ] Fallback behavior is tested (not just the happy path)
- [ ] Users receive meaningful feedback when degraded
- [ ] Degraded state is logged and monitored
- [ ] System recovers automatically when dependency returns

## Structured Error Reporting

EVERY error log MUST include:

1. **Timestamp** — when the error occurred (ISO 8601)
2. **Error type** — classification (e.g., `NetworkError`, `ValidationError`)
3. **Message** — human-readable description
4. **Context** — request ID, user ID, operation name
5. **Stack trace** — for unexpected errors only
6. **Severity** — critical, error, warning, info

### Logging Rules

1. NEVER log sensitive data (passwords, tokens, PII)
2. ALWAYS include a correlation/request ID for tracing
3. Use structured formats (JSON) — not free-text messages
4. Log at the point of handling, not at every re-throw
5. NEVER use `console.log` for error reporting in production
6. Include enough context to reproduce the issue without access to the user's session

## Root Cause Analysis

When an error occurs repeatedly:

1. **Identify the pattern** — when, how often, what triggers it
2. **Trace to the source** — follow the call stack to the originating failure
3. **Fix the source** — not the symptom, not the caller, not the wrapper
4. **Add a regression test** — prove the fix and prevent recurrence
5. **Remove the workaround** — if you added a retry or fallback for this specific issue, remove it after fixing the root cause

### Symptom vs Root Cause

| Symptom Fix | Root Cause Fix |
|-------------|---------------|
| Retry the failing request | Fix the server returning errors |
| Catch and ignore the exception | Prevent the invalid state |
| Add a null check | Fix the code that produces null |
| Increase the timeout | Fix the slow query |
| Restart the service | Fix the memory leak |

## Anti-Patterns

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| Catch-all with empty handler | Errors vanish; bugs become invisible |
| Retry without backoff | Overwhelms the failing service |
| Retry non-idempotent operations | Creates duplicates or corruption |
| Logging without context | "Error occurred" helps no one |
| Treating all errors as transient | Permanent errors waste retry budget |
| Error strings instead of error types | Cannot programmatically handle different cases |

## The Bottom Line

Prevent what you can. Handle what you cannot prevent. Report what you cannot handle. Fix root causes, not symptoms.

NEVER swallow an error. NEVER retry blindly. NEVER treat a workaround as a fix.
