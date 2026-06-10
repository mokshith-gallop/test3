# Locked Decisions for Story ac973de2-2d7b-4495-8a14-b25d2680eaf0

## Type Mapping
### Complete Hive → BigQuery Type Mapping Table

#### Scalar Types

| Hive Type | BigQuery Type | Lossy? | Notes |
|---|---|---|---|
| `STRING` | `STRING` | No | Direct 1:1 |
| `BOOLEAN` | `BOOL` | No | Direct 1:1 |
| `INT` | `INT64` | No | Widening (32→64 bit) |
| `BIGINT` | `INT64` | No | Direct 1:1; boundary values tested in AC #9 |
| `TINYINT` | `INT64` | Yes | Widening (8→64 bit); affects `sales_cube.dim_level`, `top_countries_daily.rank` |
| `SMALLINT` | `INT64` | Yes | Widening (16→64 bit); affects `sales_cube.month_key` |
| `DATE` | `DATE` | No | Direct 1:1 |
| `TIMESTAMP` | `TIMESTAMP` | No | Both microsecond precision |
| `DOUBLE` | `FLOAT64` | No | IEEE 754 double; affects `dim_warehouse.geocode.lat/lon`, `dim_geography.latitude/longitude` |
| `DECIMAL(p,s)` (all) | `NUMERIC` | Yes | BQ NUMERIC = precision 38, scale 9. All source precisions fit. Round-trip tested per AC #9 |

#### DECIMAL Precision Inventory (all → NUMERIC)

| Precision | Columns Affected |
|---|---|
| `DECIMAL(10,2)` | dim_product.unit_price, kudu_realtime_price.price/list_price/cost |
| `DECIMAL(12,2)` | fact_returns.refund_amount, returns_ledger.refund_amount, kudu_session_state.cart_value, fact_promo_redemptions.discount_amount |
| `DECIMAL(14,2)` | fact_sales.line_total, fact_payments.amount/fee_amount, fact_refunds.amount, dim_promotion.budget, agg_marketing_attribution_cube.cost |
| `DECIMAL(16,2)` | agg_daily_sales_by_store.gross/net_revenue, agg_daily_sales_by_product.gross_revenue/cogs, agg_weekly_customer_ltv.ltv_to_date, agg_monthly_supplier_performance.total_spend, agg_returns_by_reason_monthly.total_refunded, sales_cube.revenue |
| `DECIMAL(18,2)` | top_countries_daily.revenue (AC #2 explicit) |
| `DECIMAL(12,4)` | fact_inventory_snapshot.avg_cost, bridge_product_supplier.unit_cost, fact_supplier_invoice_lines.unit_cost (AC #2 explicit) |
| `DECIMAL(5,4)` | kudu_realtime_price.margin_pct, dim_payment_method.fee_pct, agg_monthly_supplier_performance.on_time_pct/fill_rate_pct, agg_daily_carrier_otd.otd_pct, fact_fraud_decisions.fraud_score (AC #2 explicit) |
| `DECIMAL(5,2)` | dim_promotion.pct_off, acid_supplier_terms_history.discount_pct (AC #2 explicit) |
| `DECIMAL(4,3)` | fact_chat_interactions.sentiment_avg, agg_weekly_customer_ltv.churn_risk, bridge_customer_segment.confidence, agg_monthly_supplier_performance.quality_score |
| `DECIMAL(6,4)` | agg_daily_sales_by_product.margin_pct |
| `DECIMAL(6,2)` | agg_monthly_supplier_performance.avg_lead_time_days |
| `DECIMAL(8,2)` | dim_payment_method.fee_flat, agg_daily_sales_by_store.avg_basket, agg_weekly_customer_ltv.avg_order_value, agg_hourly_warehouse_kpi.pick_rate_uph/avg_pick_seconds, agg_daily_carrier_otd.avg_transit_hours, agg_returns_by_reason_monthly.avg_days_to_return |
| `DECIMAL(8,4)` | agg_marketing_attribution_cube.roas |

#### Complex Types

| Hive Type | BigQuery Type | Columns Affected |
|---|---|---|
| `MAP<STRING,STRING>` | `JSON` | dim_store.attributes, dim_promotion.eligibility, fact_app_clicks.properties, fact_loyalty_events.meta |
| `STRUCT<...>` | `STRUCT<...>` | dim_supplier.primary_contact → `STRUCT<name STRING, email STRING, phone STRING>`; dim_warehouse.geocode → `STRUCT<lat FLOAT64, lon FLOAT64>`; fact_app_clicks.device → `STRUCT<platform STRING, version STRING, model STRING>` |
| `ARRAY<STRING>` | `ARRAY<STRING>` | dim_supplier.categories, dim_promotion.channels, fact_fraud_decisions.rule_signals |
| `ARRAY<STRUCT<...>>` | `ARRAY<STRUCT<...>>` | fact_shipments.tracking_events → `ARRAY<STRUCT<ts TIMESTAMP, status STRING, location STRING>>`; fact_email_engagement.clicks → `ARRAY<STRUCT<ts TIMESTAMP, url STRING>>` |

#### Kudu-Specific Type Adjustments
- Kudu `BIGINT` timestamps (epoch millis: `last_updated_ts`, `started_ts`, `last_event_ts`, `valid_from_ts`, `valid_to_ts`, `updated_ts`) → `TIMESTAMP` in BigQuery native table (kudu_session_state) or remain as row key components in Bigtable
- Kudu `PRIMARY KEY` → informational only in BigQuery; Bigtable row key in Bigtable schemas

#### Synthetic Columns Added (not in source)
These new columns are added for partitioning. Original integer partition columns are **retained** as regular non-partition columns for backward compatibility:

| Table | New Column | Type | Derived From |
|---|---|---|---|
| fact_inventory_movements | `movement_date` | `DATE` | `year`, `month`, `day` |
| fact_payments | `post_date` | `DATE` | `post_year`, `post_month` (day defaults to 1) |
| fact_shipments | `ship_date` | `DATE` | `ship_year`, `ship_month`, `ship_day` |
| fact_supplier_invoice_lines | `invoice_date` | `DATE` | `invoice_year`, `invoice_month` (day defaults to 1) |
| dim_employee_history | `eff_from_date` | `DATE` | `eff_from_year` (month/day default to 1) |
| agg_hourly_warehouse_kpi | `snapshot_ts` | `TIMESTAMP` | Parsed from `snapshot_hour` STRING |

#### Original Partition/Bucket Columns Retained as Regular Columns
All original multi-column partition fields (`year`, `month`, `day`, `region`, `post_year`, `post_month`, `ship_year`, `ship_month`, `ship_day`, `carrier_partition`, `payment_method_partition`, `warehouse_partition`, `platform_partition`, `invoice_year`, `invoice_month`, `eff_from_year`, `snapshot_hour`, `country`) are retained in the BigQuery schema as regular (non-partition) columns with their mapped types (INT→INT64, STRING→STRING). This satisfies AC #2's "every source column is present" requirement.

## Validation Strategy
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

## Implementation Approach
### DDL File Organization & Output Structure

**Output mirrors source HQL structure** — one BigQuery `.sql` file per source HQL file, written to `/workspace/project/retail/ddl/`:

| Source HQL | Output SQL | Contents |
|---|---|---|
| `03-retail-tables.hql` | `03-retail-tables.sql` | dim_date, dim_customer, dim_product, fact_sales, fact_web_session |
| `06-acid-tables.hql` | `06-acid-tables.sql` | returns_ledger |
| `10-additional-dims.hql` | `10-additional-dims.sql` | 12 dimension tables (dim_store through dim_payment_method) |
| `11-additional-facts.hql` | `11-additional-facts.sql` | 16 fact tables (fact_inventory_movements through fact_customer_complaints) |
| `12-aggregates-rollups.hql` | `12-aggregates-rollups.sql` | 8 aggregate tables |
| `13-additional-acid-tables.hql` | `13-additional-acid-tables.sql` | 4 ACID tables (acid_customer_address_history, etc.) |
| `14-kudu-realtime.hql` | `14-kudu-realtime.sql` | 4 Kudu tables: Bigtable `cbt` commands as comments + BQ external table DDL for 2 tables + BQ native table for kudu_session_state |
| `15-bridge-and-scd2.hql` | `15-bridge-and-scd2.sql` | 5 bridge tables + 2 SCD-2 history dims |

**Additionally generated:**
- `00-dataset.sql` — `CREATE SCHEMA IF NOT EXISTS` for the `retail` dataset in `acme-analytics-project`
- `99-validate-lossy-columns.sql` — SQL seed-and-verify script for AC #9 round-trip validation

**Total: 54 BigQuery tables + 3 Bigtable table schemas + 2 BigQuery external tables = 59 DDL objects across 10 files.**

### Target Project & Dataset
- All native tables: `` `acme-analytics-project.retail.<table>` ``
- External tables (Bigtable federation): `` `acme-analytics-project.retail.kudu_inventory_realtime` `` and `` `acme-analytics-project.retail.kudu_realtime_price` ``
- Scratch deployment target per AC #1: `acme-analytics-project.retail` (scratch dataset)

### Kudu Table Implementation (per locked decision)
1. **`kudu_inventory_realtime`** — Bigtable schema (cbt commands in comments) + BigQuery `CREATE EXTERNAL TABLE` with `CLOUD_BIGTABLE` format
2. **`kudu_realtime_price`** — Same pattern as above
3. **`kudu_promo_eligibility`** — Bigtable schema only (cbt commands in comments), no external table DDL
4. **`kudu_session_state`** — BigQuery native table with `CLUSTER BY session_id` (streaming append pattern with dedup view)

### Key Technical Patterns
- All `CREATE TABLE` statements use `CREATE OR REPLACE TABLE` for idempotent re-deployment
- No `STORED AS`, `TBLPROPERTIES`, `CLUSTERED BY ... INTO N BUCKETS` — all Hive storage directives are stripped
- Hive `transactional = true` properties are dropped (BigQuery is natively ACID)
- ORC/Parquet/Snappy compression directives are dropped (BigQuery manages Capacitor format internally)
- Each file begins with a header comment referencing the source HQL file for traceability

## Partitioning & Clustering
### Partitioning & Clustering Strategy for All 54 Tables

Per the locked project-level partitioning decision, all multi-column Hive partitions collapse to a single DATE/TIMESTAMP partition column, and all Hive bucketing keys become BigQuery `CLUSTER BY` columns. Secondary Hive partition dimensions move to `CLUSTER BY`.

#### Tables with Partitioning + Clustering

| Table | BQ Partition Column | BQ CLUSTER BY | Source Pattern | AC |
|---|---|---|---|---|
| `fact_sales` | `PARTITION BY sale_date` | `CLUSTER BY customer_sk` | `PARTITIONED BY (sale_date DATE) CLUSTERED BY (customer_sk) INTO 8 BUCKETS` | AC #3 ✓ |
| `fact_inventory_movements` | `PARTITION BY movement_date` | `CLUSTER BY region, sku` | `PARTITIONED BY (year, month, day, region) CLUSTERED BY (sku) INTO 32 BUCKETS` | AC #4 ✓ |
| `fact_payments` | `PARTITION BY post_date` | `CLUSTER BY payment_method_partition, invoice_no` | `PARTITIONED BY (post_year, post_month, payment_method_partition) CLUSTERED BY (invoice_no) INTO 16 BUCKETS` | AC #5 ✓ |
| `fact_shipments` | `PARTITION BY ship_date` | `CLUSTER BY carrier_partition, warehouse_sk` | `PARTITIONED BY (ship_year, ship_month, ship_day, carrier_partition) CLUSTERED BY (warehouse_sk) INTO 16 BUCKETS` | AC #6 ✓ |
| `fact_inventory_snapshot` | `PARTITION BY snapshot_date` | `CLUSTER BY sku` | `PARTITIONED BY (snapshot_date) CLUSTERED BY (sku) INTO 16 BUCKETS` | — |
| `fact_warehouse_picks` | `PARTITION BY pick_date` | `CLUSTER BY warehouse_partition, picker_sk` | `PARTITIONED BY (pick_date, warehouse_partition) CLUSTERED BY (picker_sk) INTO 8 BUCKETS` | — |
| `fact_supplier_invoice_lines` | `PARTITION BY invoice_date` | — | `PARTITIONED BY (invoice_year, invoice_month)` — synthetic DATE | — |
| `fact_web_session` | `PARTITION BY event_date` | `CLUSTER BY country` | `PARTITIONED BY (event_date, country)` — country moves to CLUSTER BY | — |
| `fact_app_clicks` | `PARTITION BY event_date` | `CLUSTER BY platform_partition` | `PARTITIONED BY (event_date, platform_partition)` | — |
| `dim_employee_history` | `PARTITION BY eff_from_date` | — | `PARTITIONED BY (eff_from_year INT)` — synthetic DATE | — |
| `agg_hourly_warehouse_kpi` | `PARTITION BY DATE(snapshot_ts)` | — | `PARTITIONED BY (snapshot_hour STRING)` — synthetic TIMESTAMP, partitioned by extracted DATE | — |

#### Tables with Partition Only (no clustering)

| Table | BQ Partition Column | Source Pattern |
|---|---|---|
| `fact_returns` | `PARTITION BY return_date` | `PARTITIONED BY (return_date DATE)` |
| `fact_refunds` | `PARTITION BY refund_date` | `PARTITIONED BY (refund_date DATE)` |
| `fact_email_engagement` | `PARTITION BY event_date` | `PARTITIONED BY (event_date DATE)` |
| `fact_chat_interactions` | `PARTITION BY start_date` | `PARTITIONED BY (start_date DATE)` |
| `fact_loyalty_events` | `PARTITION BY event_date` | `PARTITIONED BY (event_date DATE)` |
| `fact_fraud_decisions` | `PARTITION BY decision_date` | `PARTITIONED BY (decision_date DATE)` |
| `fact_promo_redemptions` | `PARTITION BY redemption_date` | `PARTITIONED BY (redemption_date DATE)` |
| `fact_customer_complaints` | `PARTITION BY created_date` | `PARTITIONED BY (created_date DATE)` |
| `agg_daily_sales_by_store` | `PARTITION BY sale_date` | `PARTITIONED BY (sale_date DATE)` |
| `agg_daily_sales_by_product` | `PARTITION BY sale_date` | `PARTITIONED BY (sale_date DATE)` |
| `agg_weekly_customer_ltv` | `PARTITION BY week_start_date` | `PARTITIONED BY (week_start_date DATE)` |
| `agg_monthly_supplier_performance` | `PARTITION BY month_start` | `PARTITIONED BY (month_start DATE)` |
| `agg_daily_carrier_otd` | `PARTITION BY ship_date` | `PARTITIONED BY (ship_date DATE)` |
| `agg_marketing_attribution_cube` | `PARTITION BY period_date` | `PARTITIONED BY (period_date DATE)` |
| `agg_returns_by_reason_monthly` | `PARTITION BY month_start` | `PARTITIONED BY (month_start DATE)` |
| `sales_cube` | `PARTITION BY as_of_date` | `PARTITIONED BY (as_of_date DATE)` |
| `bridge_customer_segment` | `PARTITION BY snapshot_date` | `PARTITIONED BY (snapshot_date DATE)` |
| `bridge_promo_eligibility` | `PARTITION BY load_date` | `PARTITIONED BY (load_date DATE)` |

#### Tables with Clustering Only (ACID tables — no partition in source, cluster from bucket key)

| Table | BQ CLUSTER BY | Source Pattern | AC |
|---|---|---|---|
| `returns_ledger` | `CLUSTER BY return_id` | `CLUSTERED BY (return_id) INTO 4 BUCKETS` | AC #7 ✓ |
| `acid_customer_address_history` | `CLUSTER BY customer_sk` | `CLUSTERED BY (customer_sk) INTO 8 BUCKETS` | — |
| `acid_supplier_terms_history` | `CLUSTER BY supplier_sk` | `CLUSTERED BY (supplier_sk) INTO 4 BUCKETS` | — |
| `acid_loyalty_points_ledger` | `CLUSTER BY member_id` | `CLUSTERED BY (member_id) INTO 8 BUCKETS` | — |
| `acid_inventory_adjustments_log` | `CLUSTER BY adjustment_id` | `CLUSTERED BY (adjustment_id) INTO 4 BUCKETS` | — |

#### Tables with No Partition or Clustering (small dimensions, bridges, reference tables)

All unpartitioned/unbucketed source tables remain unpartitioned in BigQuery:

`dim_date`, `dim_customer`, `dim_product`, `dim_store`, `dim_supplier`, `dim_employee`, `dim_promotion`, `dim_warehouse`, `dim_currency`, `dim_geography`, `dim_color`, `dim_size`, `dim_brand`, `dim_category`, `dim_payment_method`, `top_countries_daily`, `bridge_product_attribute`, `bridge_product_supplier`, `bridge_employee_role`, `dim_store_history`

#### Kudu Tables (per locked Kudu decision)

| Table | Target | Partition/Cluster | AC |
|---|---|---|---|
| `kudu_session_state` | BQ native | `CLUSTER BY session_id` | AC #8 ✓ |
| `kudu_inventory_realtime` | Bigtable + BQ external | Row key: `warehouse_id#sku` | AC #8 ✓ |
| `kudu_realtime_price` | Bigtable + BQ external | Row key: `sku#store_id` | AC #8 ✓ |
| `kudu_promo_eligibility` | Bigtable only | Row key: `customer_id#promo_id` | AC #8 ✓ |
