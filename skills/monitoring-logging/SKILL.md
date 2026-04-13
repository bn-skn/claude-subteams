---
name: monitoring-logging
description: Use when implementing structured logging, health checks, alerting, or observability for services
---

# Monitoring and Logging

## Overview

Observability is not optional. Without structured logging and monitoring, debugging production issues becomes guesswork.

**Core principle:** Every service MUST produce structured logs, expose health checks, and define alert rules before going live.

## When to Use

- Adding logging to a new or existing service
- Setting up health check endpoints
- Defining alert rules for error rate, latency, or resource usage
- Implementing correlation IDs for request tracing
- Integrating with OpenTelemetry

## Structured Logging

### Format Requirements
1. ALWAYS use JSON format for log output
2. MUST include these fields in every log entry:
   - `timestamp` (ISO 8601)
   - `level` (debug, info, warn, error)
   - `message` (human-readable description)
   - `service` (service name)
   - `correlationId` (request trace identifier)
3. NEVER log sensitive data (passwords, tokens, PII)
4. ALWAYS sanitize user input before logging

### Log Levels
| Level | When to Use |
|-------|------------|
| `debug` | Development-only detail, disabled in production |
| `info` | Normal operations: startup, request handled, job completed |
| `warn` | Recoverable issues: retry succeeded, fallback used |
| `error` | Failures requiring attention: unhandled exception, service down |

### Example Log Entry
```json
{
  "timestamp": "2026-01-15T10:30:00.000Z",
  "level": "error",
  "message": "Payment processing failed",
  "service": "payment-api",
  "correlationId": "abc-123-def",
  "error": "TimeoutError",
  "duration_ms": 5000,
  "userId": "usr_***"
}
```

## Correlation IDs

### Implementation Checklist
1. Generate a unique ID at the entry point (API gateway, message consumer)
2. Pass the ID through all downstream service calls via headers
3. Include the ID in every log entry for the request lifecycle
4. ALWAYS propagate correlation IDs across async boundaries
5. Use `X-Correlation-ID` or `X-Request-ID` header by convention

## Log Aggregation

### Strategy Checklist
1. Centralize logs from all services into a single platform
2. Use structured queries to filter by service, level, or correlation ID
3. Set retention policies (7 days debug, 30 days info, 90 days error)
4. Index on correlationId, service, level, and timestamp
5. NEVER rely solely on local log files in production

## Health Check Endpoints

### Requirements
1. Expose `GET /health` returning 200 when service is healthy
2. Check all critical dependencies (database, cache, external APIs)
3. Return degraded status if non-critical dependencies are down
4. MUST respond within 5 seconds
5. NEVER include sensitive information in health check responses

### Response Format
```json
{
  "status": "healthy",
  "version": "1.2.3",
  "uptime_seconds": 3600,
  "checks": {
    "database": "healthy",
    "cache": "healthy",
    "external_api": "degraded"
  }
}
```

## Alert Rules

### MUST Alert On
1. Error rate exceeds 1% of requests over 5-minute window
2. P95 latency exceeds SLA threshold (define per service)
3. Disk usage exceeds 80%
4. Memory usage exceeds 85%
5. Health check failures for 3 consecutive checks

### Alert Configuration Checklist
1. Define severity levels: critical (page), warning (notify), info (log)
2. Set appropriate thresholds to avoid alert fatigue
3. Include runbook links in alert descriptions
4. Route critical alerts to on-call, warnings to channel
5. ALWAYS include context: which service, which metric, current value

## OpenTelemetry Basics

### Integration Checklist
1. Instrument HTTP handlers with automatic span creation
2. Add custom spans for database queries and external calls
3. Propagate trace context across service boundaries
4. Export traces, metrics, and logs to your observability backend
5. Use semantic conventions for span and attribute naming

### Key Metrics to Track
1. Request rate (requests per second)
2. Error rate (errors per second, error percentage)
3. Duration (P50, P95, P99 latency)
4. Saturation (CPU, memory, connection pool usage)

## Critical Rules

- NEVER log at debug level in production unless explicitly enabled
- NEVER suppress errors silently; always log before swallowing
- ALWAYS include correlation IDs in error responses to clients
- MUST test health check endpoints in CI
- MUST have alerts configured before production launch

## Quick Reference

| Component | Purpose | Check Frequency |
|-----------|---------|-----------------|
| Structured logs | Debugging, audit | Continuous |
| Health checks | Availability | Every 30 seconds |
| Alert rules | Incident detection | Real-time |
| Traces | Request flow | Per-request |
