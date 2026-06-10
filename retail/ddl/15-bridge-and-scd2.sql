-- ============================================================================
-- 15-bridge-and-scd2.sql
-- BigQuery DDL for bridge tables (M:N) and SCD-2 history dimensions.
-- Source: 15-bridge-and-scd2.hql
--
-- Type mappings applied:
--   BIGINT       → INT64
--   INT          → INT64
--   STRING       → STRING
--   DATE         → DATE
--   BOOLEAN      → BOOL
--   DECIMAL(p,s) → NUMERIC
--
-- Hive-specific directives stripped:
--   STORED AS PARQUET
--
-- Partitioning strategy:
--   bridge_customer_segment:  PARTITION BY snapshot_date
--   bridge_promo_eligibility: PARTITION BY load_date
--   dim_employee_history:     synthetic eff_from_date DATE (from eff_from_year INT)
--                             PARTITION BY eff_from_date; eff_from_year retained
--   Others: unpartitioned/unclustered
--
-- Synthetic columns added:
--   dim_employee_history.eff_from_date DATE (from eff_from_year; month/day default to 1)
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────
-- bridge_product_attribute: product M:N attribute values
-- Unpartitioned (small reference data)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.bridge_product_attribute` (
  product_sk      INT64,
  attribute_name  STRING,
  attribute_value STRING,
  primary_value   BOOL,       -- source: BOOLEAN
  sort_order      INT64
);

-- ────────────────────────────────────────────────────────────────────
-- bridge_product_supplier: product M:N supplier
-- Unpartitioned
-- DECIMAL(12,4) → NUMERIC (unit_cost)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.bridge_product_supplier` (
  product_sk       INT64,
  supplier_sk      INT64,
  primary_supplier BOOL,       -- source: BOOLEAN
  supplier_sku     STRING,
  unit_cost        NUMERIC,    -- source: DECIMAL(12,4)
  lead_time_days   INT64,
  moq              INT64,      -- min order quantity
  valid_from       DATE,
  valid_to         DATE
);

-- ────────────────────────────────────────────────────────────────────
-- bridge_customer_segment: customer M:N segment memberships
-- Source: PARTITIONED BY (snapshot_date DATE)
-- BQ: PARTITION BY snapshot_date
-- DECIMAL(4,3) → NUMERIC (confidence)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.bridge_customer_segment` (
  customer_sk   INT64,
  segment_id    STRING,
  segment_name  STRING,
  assigned_dt   DATE,
  expires_dt    DATE,
  confidence    NUMERIC,    -- source: DECIMAL(4,3)
  source        STRING,
  snapshot_date DATE
)
PARTITION BY snapshot_date;

-- ────────────────────────────────────────────────────────────────────
-- bridge_promo_eligibility: which promos a customer is eligible for
-- Source: PARTITIONED BY (load_date DATE)
-- BQ: PARTITION BY load_date
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.bridge_promo_eligibility` (
  customer_sk INT64,
  promo_sk    INT64,
  eligible    BOOL,       -- source: BOOLEAN
  reason      STRING,
  valid_from  DATE,
  valid_to    DATE,
  load_date   DATE
)
PARTITION BY load_date;

-- ────────────────────────────────────────────────────────────────────
-- bridge_employee_role: employees can hold multiple roles
-- Unpartitioned
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.bridge_employee_role` (
  employee_sk  INT64,
  role         STRING,
  primary_role BOOL,       -- source: BOOLEAN
  eff_from     DATE,
  eff_to       DATE
);

-- ────────────────────────────────────────────────────────────────────
-- dim_employee_history: non-ACID SCD-2 employee history
-- Source: PARTITIONED BY (eff_from_year INT)
-- BQ: synthetic eff_from_date DATE (from eff_from_year; month/day default to 1)
--     PARTITION BY eff_from_date
--     Original eff_from_year retained as regular INT64 column.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_employee_history` (
  history_id    INT64,
  employee_sk   INT64,
  role          STRING,
  department    STRING,
  home_store_sk INT64,
  salary_band   STRING,
  eff_from      DATE,
  eff_to        DATE,
  is_current    BOOL,       -- source: BOOLEAN
  -- Original partition column retained as regular column
  eff_from_year INT64,
  -- Synthetic partition column (derived from eff_from_year; month/day default to 1)
  eff_from_date DATE
)
PARTITION BY eff_from_date;

-- ────────────────────────────────────────────────────────────────────
-- dim_store_history: non-ACID SCD-2 store history
-- Unpartitioned
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_store_history` (
  history_id          INT64,
  store_sk            INT64,
  store_type          STRING,
  manager_employee_sk INT64,
  sq_ft               INT64,
  eff_from            DATE,
  eff_to              DATE,
  is_current          BOOL,       -- source: BOOLEAN
  change_reason       STRING
);
