# Validation Strategy

### Validation Strategy for All 9 Acceptance Criteria

#### AC #1: Zero-Error DDL Deployment
- **Method**: Execute all 8 DDL `.sql` files sequentially against `acme-analytics-project.retail` scratch dataset. The `00-dataset.sql` file runs first to create the dataset. Each file uses `CREATE OR REPLACE TABLE` for idempotency.
- **Verification**: Query `INFORMATION_SCHEMA.TABLES` and assert exactly 54 tables are created (42 named in AC #1 + 12 additional dims). Separately verify 2 external tables exist for Kudu federation.
- **Pass criteria**: Zero SQL errors during execution.

#### AC #2: Column Parity & Type Correctness
- **Method**: Query `INFORMATION_SCHEMA.COLUMNS` for each table and compare against the source HQL column inventory.
- **Checks per table**:
  1. Every source column name exists in BigQuery (including original partition columns retained as regular columns)
  2. Synthetic columns (`movement_date`, `post_date`, `ship_date`, `invoice_date`, `eff_from_date`, `snapshot_ts`) are present as additions
  3. Type mappings match the locked type mapping table exactly:
     - All `TINYINT`/`SMALLINT` columns → `INT64`
     - All `DECIMAL(p,s)` columns → `NUMERIC`
     - All `MAP<STRING,STRING>` columns → `JSON`
     - All `ARRAY<STRUCT<...>>` columns → confirmed via `ARRAY` data type with correct struct fields
     - All `STRUCT<...>` columns → confirmed via `STRUCT` sub-field inspection
- **Pass criteria**: Zero column mismatches across all 54 tables.

#### ACs #3–#6: Partitioning & Clustering Verification
- **Method**: Query `INFORMATION_SCHEMA.TABLE_OPTIONS` and `INFORMATION_SCHEMA.COLUMNS` to extract partition and clustering metadata for each AC-specified table.
- **AC #3** (`fact_sales`): Verify `partition_column = sale_date`, `clustering_columns = [customer_sk]`
- **AC #4** (`fact_inventory_movements`): Verify `partition_column = movement_date`, `clustering_columns = [region, sku]`
- **AC #5** (`fact_payments`): Verify `partition_column = post_date`, `clustering_columns = [payment_method_partition, invoice_no]`
- **AC #6** (`fact_shipments`): Verify `partition_column = ship_date`, `clustering_columns = [carrier_partition, warehouse_sk]`
- **Pass criteria**: Metadata exactly matches the specified partition/cluster configuration per AC.

#### AC #7: ACID Table Conversion (returns_ledger)
- **Method**: Verify `returns_ledger` is created as a native BigQuery table (not external), has no transactional properties in `TABLE_OPTIONS`, and has `CLUSTER BY return_id`.
- **Pass criteria**: Table exists, is native, has correct clustering, no Hive ACID properties.

#### AC #8: Kudu Table Conversion
- **Method**: Verify per the locked Kudu strategy:
  1. `kudu_session_state` — BQ native table exists with `CLUSTER BY session_id`
  2. `kudu_inventory_realtime` — BQ external table exists with `format = CLOUD_BIGTABLE`; Bigtable `cbt` commands documented in DDL comments
  3. `kudu_realtime_price` — BQ external table exists with `format = CLOUD_BIGTABLE`; Bigtable `cbt` commands documented
  4. `kudu_promo_eligibility` — Bigtable `cbt` commands documented in DDL comments (no BQ table)
- **Note**: External table creation will fail without a live Bigtable instance. The DDL is verified syntactically; deployment verification requires the Bigtable instance to be provisioned first.
- **Pass criteria**: DDL is syntactically valid; native table deploys successfully; external table DDL is present and structurally correct.

#### AC #9: Lossy-Column Round-Trip Validation (`99-validate-lossy-columns.sql`)
- **Method**: A single SQL script that performs seed-and-verify for every lossy-mapped column across all 54 tables.
- **Structure**:
  1. **Seed phase**: `INSERT INTO` each table with a single canonical edge-value row containing boundary values for every lossy column:
     - `TINYINT` boundaries: 127, -128 → inserted as INT64
     - `SMALLINT` boundaries: 32767, -32768 → inserted as INT64
     - `BIGINT` boundaries: 9223372036854775807, -9223372036854775808 → INT64
     - `DECIMAL(18,2)`: 9999999999999999.99 → NUMERIC
     - `DECIMAL(5,4)`: 9.9999 → NUMERIC
     - `DECIMAL(12,4)`: 99999999.9999 → NUMERIC
     - `DECIMAL(5,2)`: 999.99 → NUMERIC
     - `FLOAT64/DOUBLE`: ±1.7976931348623157e+308, Infinity, NaN
     - `TIMESTAMP`: '0001-01-01 00:00:00', '9999-12-31 23:59:59.999999'
     - `MAP→JSON`: `'{"key1":"val1","key2":"val2"}'`
     - `ARRAY<STRING>`: `['a','b','c']`
     - `ARRAY<STRUCT<...>>`: nested struct array with populated fields
     - `STRUCT<...>`: fully populated struct
  2. **Verify phase**: `SELECT` the seeded row back and use `EXCEPT DISTINCT` against the expected literal values. Zero rows returned = exact round-trip match.
  3. **Cleanup phase**: `DELETE` the seeded test rows.
- **Coverage**: Every table that contains at least one lossy column gets a seed+verify block. The script outputs a final `SELECT` summarizing pass/fail per table.
- **Lossy column census** (columns requiring round-trip verification):

| Lossy Category | Column Count | Tables Affected |
|---|---|---|
| `TINYINT/SMALLINT → INT64` | 3 | sales_cube (2), top_countries_daily (1) |
| `DECIMAL → NUMERIC` (all precisions) | ~65 | 30+ tables across facts, aggs, dims, bridges, ACID |
| `DOUBLE → FLOAT64` | 4 | dim_warehouse.geocode (2), dim_geography (2) |
| `TIMESTAMP` | ~25 | All tables with TIMESTAMP columns |
| `MAP → JSON` | 4 | dim_store, dim_promotion, fact_app_clicks, fact_loyalty_events |
| `BIGINT boundary` | ~30 | All surrogate key columns (customer_sk, product_sk, etc.) |

- **Pass criteria**: Zero rows returned from any `EXCEPT DISTINCT` check. 0 unprobed lossy columns (every column in the census above has a test case).
