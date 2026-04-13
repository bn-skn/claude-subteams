---
name: data-engineering
description: Use when building data pipelines, ETL processes, data validation, or data quality systems
type: flexible
---

# Data Engineering

## Overview

Data pipelines are only as reliable as their weakest validation step. Garbage in, garbage out applies at every stage.

**Core principle:** ALWAYS validate data at boundaries. NEVER trust upstream data without explicit checks.

## When to Use

- Building or modifying ETL/ELT pipelines
- Adding data validation to inputs or outputs
- Implementing parser resilience (retry, fallback, partial results)
- Setting up data quality checks
- Deciding between batch and streaming processing

## Data Validation

### Schema Validation Checklist
1. Define explicit schemas for all data inputs (Zod for TypeScript, pydantic for Python)
2. Validate at ingestion boundary BEFORE any processing
3. Reject invalid records with clear error messages including the failing field and value
4. NEVER silently coerce invalid data into a "close enough" value
5. ALWAYS log validation failures with enough context to debug

### Zod Example
```typescript
const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  createdAt: z.string().datetime(),
  age: z.number().int().min(0).max(150),
});
```

### Pydantic Example
```python
class User(BaseModel):
    id: UUID
    email: EmailStr
    created_at: datetime
    age: int = Field(ge=0, le=150)
```

### Validation Rules
1. MUST validate data types, ranges, and formats
2. MUST check for required fields and reject if missing
3. MUST handle null/undefined/empty string distinctly
4. NEVER rely on database constraints as your only validation
5. ALWAYS validate referential integrity before writes

## ETL Patterns

### Extract
1. Define source connection with retry configuration
2. Implement incremental extraction using watermarks (timestamps, sequence IDs)
3. Log extraction metrics: record count, byte size, duration
4. MUST handle source unavailability with backoff and retry
5. NEVER extract more data than needed (use filters, projections)

### Transform
1. Apply transformations as pure functions (input in, output out, no side effects)
2. Chain transformations in a clear, ordered pipeline
3. Validate output of each transformation step
4. MUST preserve data lineage (track where each record originated)
5. NEVER mutate source data; always create new records

### Load
1. Use idempotent writes (upsert, merge) to handle reruns safely
2. Load in batches with configurable batch size
3. Verify record counts match between extract and load phases
4. MUST handle partial load failures without corrupting existing data
5. ALWAYS write to staging tables first, then swap to production

### Pipeline Structure
```
Extract (source)
  -> Validate (schema check)
    -> Transform (business logic)
      -> Validate (output schema check)
        -> Load (staging)
          -> Verify (count check)
            -> Promote (staging -> production)
```

## Parser Resilience

### Retry Strategy
1. Implement exponential backoff for transient failures
2. Set maximum retry count (3-5 attempts)
3. Log each retry attempt with failure reason
4. MUST distinguish between retryable and non-retryable errors
5. NEVER retry on validation errors (bad data won't improve on retry)

### Fallback Strategy
1. Define fallback data sources for critical pipelines
2. Use cached/stale data with a staleness indicator when source is unavailable
3. MUST notify operators when falling back
4. NEVER silently use fallback data without logging

### Partial Results
1. Process valid records even when some records fail validation
2. Quarantine invalid records to a dead-letter queue for manual review
3. Report success rate: "Processed 950/1000 records, 50 quarantined"
4. MUST set minimum success threshold (e.g., fail pipeline if < 90% valid)
5. ALWAYS provide a mechanism to reprocess quarantined records

## Data Quality Checks

### Checklist (Run After Every Pipeline Execution)
1. **Completeness**: Are all expected records present? Compare source and target counts
2. **Freshness**: Is data within expected recency? Check latest timestamp
3. **Uniqueness**: Are there unexpected duplicates? Check primary key uniqueness
4. **Consistency**: Do aggregates match expected ranges? Check sums, averages
5. **Accuracy**: Do sample records match source? Spot-check random records

### Alerting on Quality Failures
1. MUST alert when any quality check fails
2. Include the specific check that failed and current vs expected values
3. Block downstream consumers when quality is below threshold
4. NEVER allow bad data to propagate to downstream systems

## Batch vs Streaming

### Choose Batch When
1. Data freshness requirement is hours or days
2. Processing requires full dataset context (aggregations, joins)
3. Source provides data in bulk dumps
4. Cost efficiency is more important than latency

### Choose Streaming When
1. Data freshness requirement is seconds or minutes
2. Events need near-real-time reaction (alerts, notifications)
3. Source produces continuous event stream
4. Individual records can be processed independently

### Hybrid Approach
1. Use streaming for time-sensitive data, batch for historical backfill
2. MUST ensure both paths produce consistent results (lambda/kappa architecture)
3. ALWAYS have a batch fallback for streaming pipeline failures

## Critical Rules

- NEVER skip validation at data boundaries
- NEVER silently drop or coerce invalid records
- ALWAYS make pipelines idempotent (safe to rerun)
- MUST log record counts at every pipeline stage
- MUST have data quality checks before downstream consumption
- ALWAYS quarantine bad data rather than discarding it

## Quick Reference

| Stage | Key Activities | Success Criteria |
|-------|---------------|------------------|
| Extract | Connect, filter, retry | All expected records fetched |
| Validate | Schema check, type check | Invalid records quarantined |
| Transform | Business logic, enrichment | Pure functions, lineage preserved |
| Load | Upsert, batch, verify | Counts match, idempotent |
| Quality | Completeness, freshness, uniqueness | All checks passing |
