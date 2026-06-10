-- ============================================================================
-- 12-aggregates-rollups.sql
-- BigQuery DDL for aggregate/rollup tables.
-- Source: 12-aggregates-rollups.hql
--
-- Type mappings applied:
--   BIGINT       → INT64
--   INT          → INT64
--   STRING       → STRING
--   DATE         → DATE
--   DECIMAL(p,s) → NUMERIC
--
-- Hive-specific directives stripped:
--   STORED AS PARQUET, TBLPROPERTIES
--
-- Partitioning strategy:
--   All tables partitioned by their source DATE partition column.
--   Exception: agg_hourly_warehouse_kpi — source partitions by STRING
--   (snapshot_hour). Synthetic TIMESTAMP column (snapshot_ts) added;
--   partitioned by DATE(snapshot_ts). Original snapshot_hour retained.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────
-- agg_daily_sales_by_store
-- Source: PARTITIONED BY (sale_date DATE)
-- BQ: PARTITION BY sale_date
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_daily_sales_by_store` (
  store_sk      INT64,
  gross_revenue NUMERIC,    -- source: DECIMAL(16,2)
  net_revenue   NUMERIC,    -- source: DECIMAL(16,2)
  units_sold    INT64,
  txn_count     INT64,
  avg_basket    NUMERIC,    -- source: DECIMAL(12,2)
  sale_date     DATE
)
PARTITION BY sale_date;

-- ────────────────────────────────────────────────────────────────────
-- agg_daily_sales_by_product
-- Source: PARTITIONED BY (sale_date DATE)
-- BQ: PARTITION BY sale_date
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_daily_sales_by_product` (
  product_sk    INT64,
  units_sold    INT64,
  gross_revenue NUMERIC,    -- source: DECIMAL(16,2)
  margin_pct    NUMERIC,    -- source: DECIMAL(6,4)
  cogs          NUMERIC,    -- source: DECIMAL(16,2)
  return_units  INT64,
  net_units     INT64,
  sale_date     DATE
)
PARTITION BY sale_date;

-- ────────────────────────────────────────────────────────────────────
-- agg_weekly_customer_ltv: cumulative customer lifetime value
-- Source: PARTITIONED BY (week_start_date DATE)
-- BQ: PARTITION BY week_start_date
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_weekly_customer_ltv` (
  customer_sk         INT64,
  ltv_to_date         NUMERIC,    -- source: DECIMAL(16,2)
  orders_to_date      INT64,
  avg_order_value     NUMERIC,    -- source: DECIMAL(12,2)
  days_since_last_order INT64,
  rfm_score           STRING,
  churn_risk          NUMERIC,    -- source: DECIMAL(4,3)
  week_start_date     DATE
)
PARTITION BY week_start_date;

-- ────────────────────────────────────────────────────────────────────
-- agg_monthly_supplier_performance
-- Source: PARTITIONED BY (month_start DATE)
-- BQ: PARTITION BY month_start
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_monthly_supplier_performance` (
  supplier_sk        INT64,
  orders_placed      INT64,
  units_received     INT64,
  on_time_pct        NUMERIC,    -- source: DECIMAL(5,4)
  fill_rate_pct      NUMERIC,    -- source: DECIMAL(5,4)
  avg_lead_time_days NUMERIC,    -- source: DECIMAL(6,2)
  quality_score      NUMERIC,    -- source: DECIMAL(4,3)
  total_spend        NUMERIC,    -- source: DECIMAL(16,2)
  month_start        DATE
)
PARTITION BY month_start;

-- ────────────────────────────────────────────────────────────────────
-- agg_hourly_warehouse_kpi: warehouse operational metrics
-- Source: PARTITIONED BY (snapshot_hour STRING)
-- BQ: Synthetic snapshot_ts TIMESTAMP column added.
--     PARTITION BY DATE(snapshot_ts)
--     Original snapshot_hour retained as regular STRING column.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_hourly_warehouse_kpi` (
  warehouse_sk     INT64,
  units_in         INT64,
  units_picked     INT64,
  units_shipped    INT64,
  pick_rate_uph    NUMERIC,    -- source: DECIMAL(8,2)
  backlog_units    INT64,
  avg_pick_seconds NUMERIC,    -- source: DECIMAL(8,2)
  -- Original partition column retained as regular column
  snapshot_hour    STRING,
  -- Synthetic partition column (parsed from snapshot_hour)
  snapshot_ts      TIMESTAMP
)
PARTITION BY DATE(snapshot_ts);

-- ────────────────────────────────────────────────────────────────────
-- agg_daily_carrier_otd: on-time-delivery rate per carrier
-- Source: PARTITIONED BY (ship_date DATE)
-- BQ: PARTITION BY ship_date
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_daily_carrier_otd` (
  carrier           STRING,
  shipments_total   INT64,
  delivered_on_time INT64,
  delivered_late    INT64,
  in_transit        INT64,
  otd_pct           NUMERIC,    -- source: DECIMAL(5,4)
  avg_transit_hours NUMERIC,    -- source: DECIMAL(8,2)
  ship_date         DATE
)
PARTITION BY ship_date;

-- ────────────────────────────────────────────────────────────────────
-- agg_marketing_attribution_cube: pre-aggregated CUBE for BI tools
-- Source: PARTITIONED BY (period_date DATE)
-- BQ: PARTITION BY period_date
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_marketing_attribution_cube` (
  channel            STRING,
  campaign_sk        INT64,
  region             STRING,
  attributed_revenue NUMERIC,    -- source: DECIMAL(16,2)
  attributed_units   INT64,
  cost               NUMERIC,    -- source: DECIMAL(14,2)
  roas               NUMERIC,    -- source: DECIMAL(8,4)
  grouping_id        INT64,
  period_date        DATE
)
PARTITION BY period_date;

-- ────────────────────────────────────────────────────────────────────
-- agg_returns_by_reason_monthly
-- Source: PARTITIONED BY (month_start DATE)
-- BQ: PARTITION BY month_start
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.agg_returns_by_reason_monthly` (
  reason_code        STRING,
  return_count       INT64,
  return_units       INT64,
  total_refunded     NUMERIC,    -- source: DECIMAL(16,2)
  avg_days_to_return NUMERIC,    -- source: DECIMAL(8,2)
  month_start        DATE
)
PARTITION BY month_start;
