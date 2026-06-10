-- ============================================================================
-- 13-additional-acid-tables.sql
-- BigQuery DDL for additional Hive ACID tables converted to native BigQuery.
-- Source: 13-additional-acid-tables.hql
--
-- Conversion notes:
--   - All Hive ACID properties stripped (transactional=true,
--     transactional_properties, orc.compress, bucketing_version).
--     BigQuery is natively ACID — no special table properties required.
--   - STORED AS ORC → dropped (BigQuery manages Capacitor format internally)
--   - CLUSTERED BY (col) INTO N BUCKETS → CLUSTER BY col
--   - Hive DML statements (UPDATE, DELETE) are NOT included here;
--     they belong in ETL/pipeline code, not in DDL.
--
-- Type mappings applied:
--   BIGINT       → INT64
--   INT          → INT64
--   STRING       → STRING
--   TIMESTAMP    → TIMESTAMP
--   BOOLEAN      → BOOL
--   DECIMAL(p,s) → NUMERIC
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────
-- acid_customer_address_history: SCD-2 customer address tracking
-- Source: CLUSTERED BY (customer_sk) INTO 8 BUCKETS, ORC, transactional=true
-- BQ: native table, CLUSTER BY customer_sk
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.acid_customer_address_history` (
  history_id      INT64,
  customer_sk     INT64,
  address_line1   STRING,
  address_city    STRING,
  address_region  STRING,
  address_country STRING,
  address_postal  STRING,
  eff_from        TIMESTAMP,
  eff_to          TIMESTAMP,
  is_current      BOOL,       -- source: BOOLEAN
  change_reason   STRING
)
CLUSTER BY customer_sk;

-- ────────────────────────────────────────────────────────────────────
-- acid_supplier_terms_history: SCD-2 supplier payment-terms changes
-- Source: CLUSTERED BY (supplier_sk) INTO 4 BUCKETS, ORC, transactional=true
-- BQ: native table, CLUSTER BY supplier_sk
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.acid_supplier_terms_history` (
  history_id         INT64,
  supplier_sk        INT64,
  payment_terms_days INT64,
  discount_pct       NUMERIC,    -- source: DECIMAL(5,2)
  eff_from           TIMESTAMP,
  eff_to             TIMESTAMP,
  is_current         BOOL,       -- source: BOOLEAN
  changed_by         STRING
)
CLUSTER BY supplier_sk;

-- ────────────────────────────────────────────────────────────────────
-- acid_loyalty_points_ledger: live earn/redeem ledger
-- Source: CLUSTERED BY (member_id) INTO 8 BUCKETS, ORC, transactional=true
-- BQ: native table, CLUSTER BY member_id
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.acid_loyalty_points_ledger` (
  entry_id        INT64,
  member_id       STRING,
  points_delta    INT64,
  running_balance INT64,
  event_ts        TIMESTAMP,
  event_type      STRING,
  reference_id    STRING,
  expiry_ts       TIMESTAMP
)
CLUSTER BY member_id;

-- ────────────────────────────────────────────────────────────────────
-- acid_inventory_adjustments_log: manual inventory adjustments (audit-mandatory)
-- Source: CLUSTERED BY (adjustment_id) INTO 4 BUCKETS, ORC, transactional=true
-- BQ: native table, CLUSTER BY adjustment_id
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.acid_inventory_adjustments_log` (
  adjustment_id  INT64,
  warehouse_sk   INT64,
  sku            STRING,
  quantity_delta INT64,
  reason_code    STRING,
  notes          STRING,
  adjusted_by    STRING,
  adjusted_at    TIMESTAMP,
  approved_by    STRING,
  approved_at    TIMESTAMP
)
CLUSTER BY adjustment_id;
