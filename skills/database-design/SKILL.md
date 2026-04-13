---
name: database-design
description: Guidelines for database schema design, migration management, query optimization, and SQLite-specific configuration including WAL mode and FTS5.
---

# Database Design

## When to Apply

Use this skill when designing schemas, writing migrations, optimizing queries, or reviewing database changes. Flexible -- adapt to the specific database engine, but follow the core principles.

## Migration Management

1. ALWAYS use numbered migration files: `001-create-users.sql`, `002-add-email-index.sql`
2. Every migration MUST be reversible -- include both `up` and `down` scripts
3. Test migrations on a copy of production data before applying
4. NEVER modify an already-applied migration -- create a new one instead
5. ALWAYS back up the database before running migrations in production
6. Include migration tests that verify both `up` and `down` work correctly
7. Migration files MUST be idempotent where possible (`CREATE TABLE IF NOT EXISTS`)

## Migration File Format

```sql
-- Migration: 003-add-user-roles
-- Created: YYYY-MM-DD

-- Up
ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user';
CREATE INDEX idx_users_role ON users(role);

-- Down
DROP INDEX IF EXISTS idx_users_role;
ALTER TABLE users DROP COLUMN role;
```

## Schema Design

### Normalization

1. Start with 3NF (Third Normal Form) as the default
2. Denormalize only with measured performance evidence -- document the trade-off in an ADR
3. NEVER duplicate data across tables without a documented reason
4. Use foreign keys to enforce referential integrity

### Indexes

1. ALWAYS index foreign key columns
2. Index columns used in WHERE, JOIN, and ORDER BY clauses
3. Use composite indexes for multi-column queries (leftmost prefix rule)
4. NEVER create unused indexes -- they slow down writes
5. Review index usage periodically: drop indexes with zero reads
6. For partial matches, put the most selective column first in composite indexes

### Constraints

1. ALWAYS define NOT NULL unless the column is genuinely optional
2. Use CHECK constraints for domain validation (`CHECK (age >= 0)`)
3. Use UNIQUE constraints for natural keys (`UNIQUE (email)`)
4. Define DEFAULT values for columns with sensible defaults
5. Use foreign key constraints with appropriate ON DELETE behavior (CASCADE, SET NULL, RESTRICT)

### Naming Conventions

1. Tables: plural snake_case (`users`, `order_items`)
2. Columns: singular snake_case (`created_at`, `user_id`)
3. Indexes: `idx_<table>_<columns>` (`idx_users_email`)
4. Foreign keys: `fk_<table>_<referenced_table>` (`fk_orders_users`)
5. NEVER abbreviate column names -- clarity over brevity

## Query Optimization

1. ALWAYS use EXPLAIN (or EXPLAIN ANALYZE) to verify query plans for complex queries
2. Watch for N+1 queries -- use JOINs or batch loading instead
3. NEVER use `SELECT *` in application code -- list specific columns
4. Use LIMIT for paginated queries
5. Prefer EXISTS over IN for subqueries with large result sets
6. Use prepared statements to prevent SQL injection and improve performance

### N+1 Detection

```
Red flag pattern:
- Loop fetching related records one at a time
- Example: fetch all orders, then fetch user for each order individually

Fix:
- Use JOIN: SELECT o.*, u.name FROM orders o JOIN users u ON o.user_id = u.id
- Use batch: SELECT * FROM users WHERE id IN (...)
```

## Backup Strategy

1. ALWAYS back up before running migrations
2. Automate daily backups for production
3. Test backup restoration regularly (untested backups are not backups)
4. Store backups in a different location than the database
5. Document recovery time objective (RTO) and recovery point objective (RPO)

## SQLite-Specific Guidelines

1. Enable WAL mode for concurrent reads with writes:

```sql
PRAGMA journal_mode=WAL;
```

2. Use FTS5 for full-text search:

```sql
CREATE VIRTUAL TABLE docs_fts USING fts5(title, body, content=docs, content_rowid=id);
```

3. Set recommended PRAGMAs for production:

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;
PRAGMA cache_size=-20000;  -- 20MB cache
```

4. SQLite has no concurrent writes -- design around this (queue writes, batch operations)
5. Use INTEGER PRIMARY KEY for auto-increment (SQLite-specific optimization)
6. NEVER store large blobs in SQLite -- use the filesystem and store paths

## Design Checklist

1. [ ] Migration files are numbered and reversible
2. [ ] Schema is at least 3NF (denormalization documented if used)
3. [ ] All foreign keys are indexed
4. [ ] NOT NULL and CHECK constraints applied where appropriate
5. [ ] Complex queries verified with EXPLAIN
6. [ ] No N+1 query patterns
7. [ ] Backup strategy documented and tested
8. [ ] SQLite PRAGMAs configured (if using SQLite)
9. [ ] Naming conventions followed consistently

## Red Flags

- Migration modifies an already-applied migration -- create a new migration instead
- SELECT * in application code -- specify columns explicitly
- Missing foreign key indexes -- add them before performance degrades
- N+1 queries in loops -- refactor to JOINs or batch loading
- No backup before migration -- always back up first
- Denormalization without documented reasoning -- add an ADR
