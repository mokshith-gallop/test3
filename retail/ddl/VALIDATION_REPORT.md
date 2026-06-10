# Wave 2 DDL Cross-Validation Report

## Summary
**Overall: ✓ ALL ACCEPTANCE CRITERIA PASS**

| AC | Description | Result |
|----|-------------|--------|
| #1 | Zero-error DDL deployment (54+1 native + 2 external) | ✓ PASS |
| #2 | Column parity & type correctness | ✓ PASS |
| #3 | fact_sales: PARTITION BY sale_date, CLUSTER BY customer_sk | ✓ PASS |
| #4 | fact_inventory_movements: PARTITION BY movement_date, CLUSTER BY region, sku | ✓ PASS |
| #5 | fact_payments: PARTITION BY post_date, CLUSTER BY payment_method_partition, invoice_no | ✓ PASS |
| #6 | fact_shipments: PARTITION BY ship_date, CLUSTER BY carrier_partition, warehouse_sk | ✓ PASS |
| #7 | returns_ledger: native BQ, no ACID props, CLUSTER BY return_id | ✓ PASS |
| #8 | Kudu conversion per locked strategy | ✓ PASS |
| #9 | Lossy-column round-trip validation script (0 unprobed) | ✓ PASS |

## File Inventory (10 files)

| File | Tables | Description |
|------|--------|-------------|
| `00-dataset.sql` | 0 | CREATE SCHEMA for acme-analytics-project.retail |
| `03-retail-tables.sql` | 7 native | Core dims + facts + rollups |
| `06-acid-tables.sql` | 1 native | returns_ledger (ACID→native) |
| `10-additional-dims.sql` | 12 native | Additional dimension tables |
| `11-additional-facts.sql` | 15 native | Additional fact tables |
| `12-aggregates-rollups.sql` | 8 native | Aggregate/rollup tables |
| `13-additional-acid-tables.sql` | 4 native | ACID tables (stripped) |
| `14-kudu-realtime.sql` | 1 native + 2 external + 3 Bigtable | Kudu conversions |
| `15-bridge-and-scd2.sql` | 7 native | Bridge + SCD-2 history |
| `99-validate-lossy-columns.sql` | — | AC #9 round-trip validation |

**Total: 55 native tables + 2 external tables + 3 Bigtable schemas = 60 DDL objects**

## AC #1: Table Count
- **55 native BigQuery tables** (54 from AC#1 list + kudu_session_state per AC#8)
- **2 external BigQuery tables** (kudu_inventory_realtime, kudu_realtime_price)
- **3 Bigtable schemas** (cbt commands in comments)
- All 42 named tables + 12 additional dims present ✓

## AC #2: Column Parity & Type Correctness
- Every source column present in BigQuery DDL ✓
- 6 synthetic columns added: movement_date, post_date, ship_date, invoice_date, eff_from_date, snapshot_ts ✓
- All original partition columns retained as regular columns ✓
- Type mappings verified:
  - TINYINT/SMALLINT → INT64 ✓
  - DECIMAL(all precisions) → NUMERIC ✓
  - MAP<STRING,STRING> → JSON (4 columns) ✓
  - ARRAY<STRUCT<...>> → ARRAY<STRUCT<...>> (2 columns) ✓
  - STRUCT<...> → STRUCT<...> (3 columns) ✓
  - ARRAY<STRING> → ARRAY<STRING> (3 columns) ✓
  - DOUBLE → FLOAT64 (4 columns) ✓
  - BOOLEAN → BOOL ✓

## ACs #3-6: Partitioning & Clustering
All verified exactly matching spec.

## AC #7: ACID Table Conversion
- returns_ledger: native BQ table, no transactional properties, CLUSTER BY return_id ✓

## AC #8: Kudu Table Conversion
- kudu_session_state: BQ native, CLUSTER BY session_id, BIGINT→TIMESTAMP ✓
- kudu_inventory_realtime: Bigtable + BQ external (CLOUD_BIGTABLE) ✓
- kudu_realtime_price: Bigtable + BQ external (CLOUD_BIGTABLE) ✓
- kudu_promo_eligibility: Bigtable only (no BQ table) ✓

## AC #9: Lossy-Column Round-Trip
- 55 tables seeded, 57 verify checks, 55 cleanup operations
- All lossy categories covered: TINYINT, SMALLINT, BIGINT, INT, DECIMAL, DOUBLE, TIMESTAMP, MAP→JSON, ARRAY, STRUCT
- 0 unprobed lossy columns ✓

## Quality Checks
- All files have source HQL traceability headers ✓
- All tables use fully-qualified backtick-quoted names ✓
- No Hive artifacts (STORED AS, TBLPROPERTIES, BUCKETS, transactional) in DDL ✓
- CREATE OR REPLACE TABLE used for idempotent deployment ✓
