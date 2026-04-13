---
name: incident-management
description: Use when responding to production incidents, conducting root cause analysis, or writing postmortems
type: flexible
---

# Incident Management

## Overview

Production incidents are inevitable. How you respond determines the impact. A structured process reduces downtime and prevents recurrence.

**Core principle:** Mitigate first, investigate second, blame never.

## When to Use

- Production service is degraded or down
- Users are reporting errors or data loss
- Alerts have fired for critical thresholds
- Writing a postmortem after an incident
- Tracking action items from past incidents

## Immediate Response

### Checklist (Do These in Order)
1. **Acknowledge the incident** within 5 minutes of detection
2. **Assess scope**: How many users affected? Which services? What severity?
3. **Communicate status** to stakeholders (Slack channel, status page)
4. **Assign roles**: Incident commander, communicator, investigators
5. **Mitigate impact**: Rollback, feature flag, traffic redirect, scale up
6. NEVER attempt root cause analysis during active mitigation
7. ALWAYS update stakeholders every 15 minutes during active incidents

### Severity Levels

| Severity | Criteria | Response Time | Update Frequency |
|----------|----------|---------------|------------------|
| SEV-1 | Service down, data loss, all users affected | Immediate | Every 15 min |
| SEV-2 | Major feature broken, many users affected | Within 30 min | Every 30 min |
| SEV-3 | Minor feature degraded, workaround exists | Within 2 hours | Every 2 hours |
| SEV-4 | Cosmetic issue, no user impact | Next business day | As resolved |

## Root Cause Analysis

### 5 Whys Method
1. State the problem clearly and specifically
2. Ask "Why did this happen?" and answer with evidence
3. Ask "Why?" again for each answer, going deeper
4. Continue until you reach the systemic root cause (usually 3-5 levels)
5. NEVER stop at "human error" -- ask why the system allowed it

### Example
```
Problem: Users could not log in for 45 minutes.
Why 1: Authentication service returned 500 errors.
Why 2: Database connection pool was exhausted.
Why 3: A slow query held connections for 30+ seconds.
Why 4: A missing index caused full table scan on users table.
Why 5: Index was dropped during a migration that was not reviewed.
Root cause: Migration review process did not include index impact check.
```

### Investigation Checklist
1. Collect all relevant logs, metrics, and traces from the incident window
2. Build a timeline of events from first signal to resolution
3. Identify the trigger event (what changed?)
4. Identify contributing factors (what made it worse?)
5. Identify detection gap (why was it not caught sooner?)

## Postmortem Template

MUST write a postmortem for every SEV-1 and SEV-2 incident.

### Required Sections
1. **Title**: Brief description of the incident
2. **Date and Duration**: When it started, when it was resolved
3. **Severity**: SEV level assigned
4. **Impact**: Number of users affected, revenue impact, data impact
5. **Timeline**: Minute-by-minute account of detection, response, resolution
6. **Root Cause**: Result of 5 Whys analysis
7. **What Went Well**: Things that worked during response
8. **What Went Poorly**: Things that slowed recovery
9. **Action Items**: Specific, assigned, time-bound tasks to prevent recurrence
10. **Lessons Learned**: Key takeaways for the team

### Timeline Format
```
HH:MM - Event description
14:02 - Alert fires: error rate > 5% on auth-service
14:05 - On-call engineer acknowledges alert
14:08 - Initial investigation: database connection errors in logs
14:15 - Decision: rollback to previous deployment
14:20 - Rollback complete, monitoring recovery
14:25 - Error rate returns to baseline, incident resolved
```

## Action Items

### Requirements for Action Items
1. Each item MUST have an owner assigned
2. Each item MUST have a due date
3. Each item MUST be specific and actionable (not "improve monitoring")
4. Track all items in BACKLOG.md
5. Review open action items weekly until resolved

### Good vs Bad Action Items

| Bad | Good |
|-----|------|
| "Improve monitoring" | "Add alert for DB connection pool > 80%, due Apr 15" |
| "Be more careful" | "Add migration CI check for index changes, due Apr 20" |
| "Fix the bug" | "Add rate limiting to /api/auth endpoint, due Apr 12" |

## Blameless Culture

### MUST Follow
1. NEVER assign blame to individuals in postmortems
2. ALWAYS focus on systemic causes and process improvements
3. Use language like "the system allowed" not "person X caused"
4. Treat incidents as learning opportunities, not failures
5. Share postmortems openly to build institutional knowledge

### NEVER Say
- "This was caused by [person]'s mistake"
- "If [person] had been more careful"
- "[Person] should have known better"

### ALWAYS Say
- "The system did not prevent this configuration error"
- "The review process did not catch the missing index"
- "The deployment pipeline lacked a rollback mechanism"

## Critical Rules

- NEVER skip the postmortem for SEV-1 or SEV-2 incidents
- NEVER attempt complex fixes during active mitigation -- rollback first
- ALWAYS communicate status before investigating
- MUST track action items to completion
- MUST conduct postmortem within 48 hours of resolution

## Quick Reference

| Phase | Key Activities | Time Constraint |
|-------|---------------|-----------------|
| Response | Acknowledge, assess, communicate, mitigate | Within minutes |
| Investigation | Logs, timeline, 5 whys | Within 24 hours |
| Postmortem | Document, action items, lessons | Within 48 hours |
| Follow-up | Track action items, verify fixes | Weekly review |
