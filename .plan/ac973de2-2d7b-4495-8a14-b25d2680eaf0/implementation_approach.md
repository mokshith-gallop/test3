# Implementation Approach

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
