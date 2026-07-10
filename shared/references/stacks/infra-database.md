# Database Review Criteria

## Migrations

- Migrations must be reversible — every `up` has a corresponding `down`
- No data loss — destructive column/table drops should migrate data first
- Large table migrations must be non-blocking — avoid long-held locks on production tables
- Migration order matters — ensure no migration references a column/table created by a later migration
- Idempotency — migrations should be safe to re-run or should guard against double application
- Test migrations against a populated database, not just an empty schema

## Indexes

- Queries filtering or joining on a column should have a supporting index
- Composite indexes — column order matters; most selective column first, or match query patterns
- Don't over-index — each index slows writes and consumes storage; justify each one
- Partial indexes — use when queries consistently filter on a subset of rows
- Unique indexes for uniqueness constraints — don't rely on application-level checks alone
- Check for unused indexes in existing schema before adding new ones

## Query Optimization

- Avoid N+1 queries — use joins, eager loading, or batch fetching
- `SELECT *` in application code — select only needed columns
- Unbounded queries — always paginate or limit; never fetch entire tables
- Subqueries vs joins — prefer joins for performance in most databases
- `EXPLAIN` / `EXPLAIN ANALYZE` for non-trivial queries — verify the query plan uses indexes
- Avoid functions on indexed columns in WHERE clauses — prevents index usage

## Transactions

- Group related writes in a transaction — partial updates corrupt data
- Keep transactions short — don't hold open transactions across network calls or user input
- Set appropriate isolation levels — default (read committed) is usually correct; document exceptions
- Handle transaction rollback on error — don't leave uncommitted transactions open
- Deadlock prevention — consistent lock ordering across transactions

## Constraints & Data Integrity

- Foreign keys for referential integrity — don't rely solely on application logic
- NOT NULL where appropriate — nullable columns should be the exception, not the default
- CHECK constraints for domain validation (e.g., positive amounts, valid status values)
- Unique constraints where business rules demand uniqueness
- Default values — set sensible defaults at the database level, not just in application code
- Cascading deletes — use with caution; prefer soft deletes or explicit cleanup for important data

## Data Types

- Use appropriate types — don't store timestamps as strings, amounts as floats, or UUIDs as text when native types exist
- Decimal/numeric for monetary values — never floating point
- Timezone-aware timestamps — store in UTC, convert at the application boundary
- Text vs varchar — use varchar with limits for validated input (emails, codes); text for freeform content
- JSON/JSONB columns — use for genuinely unstructured data, not as a substitute for proper schema design
- Enum types — prefer database enums or lookup tables over magic strings
