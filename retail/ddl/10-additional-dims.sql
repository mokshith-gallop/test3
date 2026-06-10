-- ============================================================================
-- 10-additional-dims.sql
-- BigQuery DDL for additional dimension tables.
-- Source: 10-additional-dims.hql
--
-- Type mappings applied:
--   BIGINT           → INT64
--   INT              → INT64
--   STRING           → STRING
--   DATE             → DATE
--   BOOLEAN          → BOOL
--   DOUBLE           → FLOAT64
--   DECIMAL(p,s)     → NUMERIC
--   MAP<STRING,STRING> → JSON
--   STRUCT<...>      → STRUCT<...>
--   ARRAY<STRING>    → ARRAY<STRING>
--
-- Hive-specific directives stripped:
--   STORED AS PARQUET, TBLPROPERTIES ('parquet.compression' = 'SNAPPY')
--
-- All dimension tables are unpartitioned/unclustered (small reference data).
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────
-- dim_store: retail locations + their attributes
-- MAP<STRING,STRING> → JSON (attributes)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_store` (
  store_sk            INT64,
  store_id            STRING,
  store_name          STRING,
  store_type          STRING,     -- FLAGSHIP / SUPERSTORE / OUTLET / POPUP
  region              STRING,
  city                STRING,
  state               STRING,
  country             STRING,
  open_dt             DATE,
  close_dt            DATE,
  sq_ft               INT64,
  manager_employee_sk INT64,
  attributes          JSON        -- source: MAP<STRING,STRING> — carpark, drive_thru, click_collect
);

-- ────────────────────────────────────────────────────────────────────
-- dim_supplier: vendor master
-- STRUCT<name:STRING, email:STRING, phone:STRING> → STRUCT<name STRING, email STRING, phone STRING>
-- ARRAY<STRING> (categories)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_supplier` (
  supplier_sk        INT64,
  supplier_id        STRING,
  supplier_name      STRING,
  country            STRING,
  tax_id             STRING,
  payment_terms_days INT64,
  onboard_dt         DATE,
  risk_rating        STRING,     -- A / B / C / D
  primary_contact    STRUCT<name STRING, email STRING, phone STRING>,
  categories         ARRAY<STRING>
);

-- ────────────────────────────────────────────────────────────────────
-- dim_employee: store + warehouse + corporate
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_employee` (
  employee_sk    INT64,
  employee_id    STRING,
  first_name     STRING,
  last_name      STRING,
  hire_dt        DATE,
  termination_dt DATE,
  role           STRING,
  department     STRING,
  home_store_sk  INT64,
  manager_sk     INT64,
  salary_band    STRING
);

-- ────────────────────────────────────────────────────────────────────
-- dim_promotion: promo codes / marketing offers
-- DECIMAL(5,2) → NUMERIC (pct_off)
-- DECIMAL(10,2) → NUMERIC (flat_off)
-- DECIMAL(14,2) → NUMERIC (budget)
-- ARRAY<STRING> (channels)
-- MAP<STRING,STRING> → JSON (eligibility)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_promotion` (
  promo_sk    INT64,
  promo_id    STRING,
  name        STRING,
  promo_type  STRING,     -- PCT_OFF / FLAT_OFF / BOGO / FREE_SHIP
  pct_off     NUMERIC,    -- source: DECIMAL(5,2)
  flat_off    NUMERIC,    -- source: DECIMAL(10,2)
  start_dt    DATE,
  end_dt      DATE,
  budget      NUMERIC,    -- source: DECIMAL(14,2)
  channels    ARRAY<STRING>,
  eligibility JSON        -- source: MAP<STRING,STRING>
);

-- ────────────────────────────────────────────────────────────────────
-- dim_warehouse: physical warehouses / DCs
-- STRUCT<lat:DOUBLE, lon:DOUBLE> → STRUCT<lat FLOAT64, lon FLOAT64>
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_warehouse` (
  warehouse_sk   INT64,
  warehouse_id   STRING,
  name           STRING,
  type           STRING,      -- DC / 3PL / FORWARD_HUB
  operator       STRING,
  region         STRING,
  capacity_units INT64,
  open_dt        DATE,
  geocode        STRUCT<lat FLOAT64, lon FLOAT64>
);

-- ────────────────────────────────────────────────────────────────────
-- dim_currency: ISO currency master
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_currency` (
  currency_code STRING,
  currency_name STRING,
  minor_unit    INT64,
  symbol        STRING
);

-- ────────────────────────────────────────────────────────────────────
-- dim_geography: country / region / city hierarchy
-- DOUBLE → FLOAT64 (latitude, longitude)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_geography` (
  geo_sk       INT64,
  country_iso2 STRING,
  country_name STRING,
  region_code  STRING,
  region_name  STRING,
  city         STRING,
  postal_code  STRING,
  timezone     STRING,
  latitude     FLOAT64,    -- source: DOUBLE
  longitude    FLOAT64     -- source: DOUBLE
);

-- ────────────────────────────────────────────────────────────────────
-- dim_color: product color attribute
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_color` (
  color_sk     INT64,
  color_code   STRING,
  color_name   STRING,
  color_family STRING,
  hex_code     STRING
);

-- ────────────────────────────────────────────────────────────────────
-- dim_size: size variant attribute
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_size` (
  size_sk     INT64,
  size_code   STRING,
  size_name   STRING,
  size_system STRING,      -- US / EU / UK
  sort_order  INT64
);

-- ────────────────────────────────────────────────────────────────────
-- dim_brand
-- BOOLEAN → BOOL (private_label)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_brand` (
  brand_sk       INT64,
  brand_id       STRING,
  brand_name     STRING,
  parent_company STRING,
  private_label  BOOL,      -- source: BOOLEAN
  launch_dt      DATE
);

-- ────────────────────────────────────────────────────────────────────
-- dim_category: hierarchical product category (self-referencing)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_category` (
  category_sk INT64,
  category_id STRING,
  parent_id   STRING,
  name        STRING,
  depth       INT64,
  sort_order  INT64
);

-- ────────────────────────────────────────────────────────────────────
-- dim_payment_method
-- DECIMAL(5,4) → NUMERIC (fee_pct)
-- DECIMAL(8,2) → NUMERIC (fee_flat)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_payment_method` (
  payment_method_sk INT64,
  method_code       STRING,
  method_name       STRING,
  category          STRING,     -- CARD / DIGITAL_WALLET / CRYPTO / VOUCHER
  fee_pct           NUMERIC,    -- source: DECIMAL(5,4)
  fee_flat          NUMERIC,    -- source: DECIMAL(8,2)
  settlement_days   INT64
);
