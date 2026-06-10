-- ============================================================================
-- 11-additional-facts.sql
-- BigQuery DDL for additional fact tables.
-- Source: 11-additional-facts.hql
--
-- Type mappings applied:
--   BIGINT               → INT64
--   INT                  → INT64
--   STRING               → STRING
--   DATE                 → DATE
--   TIMESTAMP            → TIMESTAMP
--   BOOLEAN              → BOOL
--   DECIMAL(p,s)         → NUMERIC
--   MAP<STRING,STRING>   → JSON
--   STRUCT<...>          → STRUCT<...>
--   ARRAY<STRING>        → ARRAY<STRING>
--   ARRAY<STRUCT<...>>   → ARRAY<STRUCT<...>>
--
-- Partitioning & clustering strategy:
--   Multi-column Hive partitions → single synthetic DATE column for BQ partition.
--   Original partition columns retained as regular columns for backward compat.
--   Hive bucket keys → CLUSTER BY.
--   Secondary Hive partition dimensions → CLUSTER BY where appropriate.
--
-- Synthetic columns added (not in source):
--   fact_inventory_movements.movement_date  DATE  (from year, month, day)
--   fact_payments.post_date                 DATE  (from post_year, post_month; day=1)
--   fact_shipments.ship_date                DATE  (from ship_year, ship_month, ship_day)
--   fact_supplier_invoice_lines.invoice_date DATE (from invoice_year, invoice_month; day=1)
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────
-- fact_inventory_movements: high-volume movement fact
-- Source: PARTITIONED BY (year INT, month INT, day INT, region STRING)
--         CLUSTERED BY (sku) INTO 32 BUCKETS
-- BQ: synthetic movement_date DATE for partition; region+sku as CLUSTER BY
--     Original year/month/day/region retained as regular columns.
-- AC #4: PARTITION BY movement_date, CLUSTER BY region, sku
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_inventory_movements` (
  movement_id   INT64,
  movement_ts   TIMESTAMP,
  sku           STRING,
  warehouse_sk  INT64,
  store_sk      INT64,
  movement_type STRING,
  quantity      INT64,
  reference_doc STRING,
  reason_code   STRING,
  operator_sk   INT64,
  -- Original partition columns retained as regular columns
  year          INT64,
  month         INT64,
  day           INT64,
  region        STRING,
  -- Synthetic partition column (derived from year, month, day)
  movement_date DATE
)
PARTITION BY movement_date
CLUSTER BY region, sku;

-- ────────────────────────────────────────────────────────────────────
-- fact_inventory_snapshot: end-of-day inventory state per warehouse+sku
-- Source: PARTITIONED BY (snapshot_date DATE)
--         CLUSTERED BY (sku) INTO 16 BUCKETS
-- BQ: PARTITION BY snapshot_date, CLUSTER BY sku
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_inventory_snapshot` (
  sku              STRING,
  warehouse_sk     INT64,
  on_hand_units    INT64,
  allocated_units  INT64,
  in_transit_units INT64,
  available_units  INT64,
  avg_cost         NUMERIC,    -- source: DECIMAL(12,4)
  last_movement_ts TIMESTAMP,
  snapshot_date    DATE
)
PARTITION BY snapshot_date
CLUSTER BY sku;

-- ────────────────────────────────────────────────────────────────────
-- fact_returns: returns processed (non-ACID; ACID version is returns_ledger)
-- Source: PARTITIONED BY (return_date DATE)
-- BQ: PARTITION BY return_date (no clustering)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_returns` (
  return_id      INT64,
  invoice_no     STRING,
  customer_sk    INT64,
  product_sk     INT64,
  return_ts      TIMESTAMP,
  quantity       INT64,
  refund_amount  NUMERIC,    -- source: DECIMAL(12,2)
  reason_code    STRING,
  return_channel STRING,
  store_sk       INT64,
  return_date    DATE
)
PARTITION BY return_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_payments: payment events
-- Source: PARTITIONED BY (post_year INT, post_month INT, payment_method_partition STRING)
--         CLUSTERED BY (invoice_no) INTO 16 BUCKETS
-- BQ: synthetic post_date DATE for partition; payment_method_partition+invoice_no as CLUSTER BY
--     Original post_year/post_month/payment_method_partition retained as regular columns.
-- AC #5: PARTITION BY post_date, CLUSTER BY payment_method_partition, invoice_no
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_payments` (
  payment_id               INT64,
  invoice_no               STRING,
  customer_sk              INT64,
  payment_method_sk        INT64,
  amount                   NUMERIC,    -- source: DECIMAL(14,2)
  currency_code            STRING,
  payment_ts               TIMESTAMP,
  auth_code                STRING,
  settlement_id            STRING,
  fee_amount               NUMERIC,    -- source: DECIMAL(10,2)
  -- Original partition columns retained as regular columns
  post_year                INT64,
  post_month               INT64,
  payment_method_partition STRING,
  -- Synthetic partition column (derived from post_year, post_month; day defaults to 1)
  post_date                DATE
)
PARTITION BY post_date
CLUSTER BY payment_method_partition, invoice_no;

-- ────────────────────────────────────────────────────────────────────
-- fact_shipments: outbound shipment events with carrier tracking
-- Source: PARTITIONED BY (ship_year INT, ship_month INT, ship_day INT, carrier_partition STRING)
--         CLUSTERED BY (warehouse_sk) INTO 16 BUCKETS
-- BQ: synthetic ship_date DATE for partition; carrier_partition+warehouse_sk as CLUSTER BY
--     Original ship_year/ship_month/ship_day/carrier_partition retained as regular columns.
-- ARRAY<STRUCT<ts:TIMESTAMP, status:STRING, location:STRING>> → ARRAY<STRUCT<...>>
-- AC #6: PARTITION BY ship_date, CLUSTER BY carrier_partition, warehouse_sk
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_shipments` (
  shipment_id     STRING,
  invoice_no      STRING,
  customer_sk     INT64,
  warehouse_sk    INT64,
  carrier         STRING,
  tracking_no     STRING,
  shipped_ts      TIMESTAMP,
  delivered_ts    TIMESTAMP,
  sla_hours       INT64,
  tracking_events ARRAY<STRUCT<ts TIMESTAMP, status STRING, location STRING>>,
  -- Original partition columns retained as regular columns
  ship_year          INT64,
  ship_month         INT64,
  ship_day           INT64,
  carrier_partition  STRING,
  -- Synthetic partition column (derived from ship_year, ship_month, ship_day)
  ship_date          DATE
)
PARTITION BY ship_date
CLUSTER BY carrier_partition, warehouse_sk;

-- ────────────────────────────────────────────────────────────────────
-- fact_refunds: financial refund settlements
-- Source: PARTITIONED BY (refund_date DATE)
-- BQ: PARTITION BY refund_date (no clustering)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_refunds` (
  refund_id     INT64,
  payment_id    INT64,
  return_id     INT64,
  customer_sk   INT64,
  amount        NUMERIC,    -- source: DECIMAL(14,2)
  currency_code STRING,
  refund_ts     TIMESTAMP,
  refund_method STRING,
  refund_date   DATE
)
PARTITION BY refund_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_app_clicks: mobile/web clickstream (sessionized)
-- Source: PARTITIONED BY (event_date DATE, platform_partition STRING)
-- BQ: PARTITION BY event_date, CLUSTER BY platform_partition
--     platform_partition retained as regular column.
-- MAP<STRING,STRING> → JSON (properties)
-- STRUCT<platform:STRING, version:STRING, model:STRING> → STRUCT<...> (device)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_app_clicks` (
  session_id         STRING,
  user_sk            INT64,
  event_ts           TIMESTAMP,
  event_type         STRING,
  screen             STRING,
  target_id          STRING,
  properties         JSON,       -- source: MAP<STRING,STRING>
  device             STRUCT<platform STRING, version STRING, model STRING>,
  event_date         DATE,
  platform_partition STRING
)
PARTITION BY event_date
CLUSTER BY platform_partition;

-- ────────────────────────────────────────────────────────────────────
-- fact_email_engagement: open / click / unsubscribe events
-- Source: PARTITIONED BY (event_date DATE)
-- BQ: PARTITION BY event_date (no clustering)
-- ARRAY<STRUCT<ts:TIMESTAMP, url:STRING>> → ARRAY<STRUCT<ts TIMESTAMP, url STRING>>
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_email_engagement` (
  send_id     STRING,
  campaign_sk INT64,
  user_sk     INT64,
  event_type  STRING,      -- OPEN / CLICK / UNSUBSCRIBE / BOUNCE
  event_ts    TIMESTAMP,
  link_url    STRING,
  clicks      ARRAY<STRUCT<ts TIMESTAMP, url STRING>>,
  event_date  DATE
)
PARTITION BY event_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_chat_interactions: customer service chat metrics
-- Source: PARTITIONED BY (start_date DATE)
-- BQ: PARTITION BY start_date (no clustering)
-- DECIMAL(4,3) → NUMERIC (sentiment_avg)
-- BOOLEAN → BOOL (resolved)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_chat_interactions` (
  chat_id       STRING,
  customer_sk   INT64,
  agent_sk      INT64,
  started_at    TIMESTAMP,
  ended_at      TIMESTAMP,
  duration_sec  INT64,
  message_count INT64,
  resolved      BOOL,       -- source: BOOLEAN
  csat_score    INT64,
  sentiment_avg NUMERIC,    -- source: DECIMAL(4,3)
  start_date    DATE
)
PARTITION BY start_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_warehouse_picks: warehouse picking events (granular)
-- Source: PARTITIONED BY (pick_date DATE, warehouse_partition STRING)
--         CLUSTERED BY (picker_sk) INTO 8 BUCKETS
-- BQ: PARTITION BY pick_date, CLUSTER BY warehouse_partition, picker_sk
--     warehouse_partition retained as regular column.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_warehouse_picks` (
  pick_id             INT64,
  warehouse_sk        INT64,
  picker_sk           INT64,
  sku                 STRING,
  quantity            INT64,
  picked_ts           TIMESTAMP,
  duration_ms         INT64,
  bin_location        STRING,
  pick_date           DATE,
  warehouse_partition STRING
)
PARTITION BY pick_date
CLUSTER BY warehouse_partition, picker_sk;

-- ────────────────────────────────────────────────────────────────────
-- fact_supplier_invoice_lines: line-level supplier invoicing
-- Source: PARTITIONED BY (invoice_year INT, invoice_month INT)
-- BQ: synthetic invoice_date DATE for partition (day defaults to 1)
--     Original invoice_year/invoice_month retained as regular columns.
-- DECIMAL(12,4) → NUMERIC (unit_cost)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_supplier_invoice_lines` (
  invoice_line_id INT64,
  invoice_no      STRING,
  supplier_sk     INT64,
  sku             STRING,
  quantity        INT64,
  unit_cost       NUMERIC,    -- source: DECIMAL(12,4)
  line_total      NUMERIC,    -- source: DECIMAL(14,2)
  currency_code   STRING,
  received_ts     TIMESTAMP,
  -- Original partition columns retained as regular columns
  invoice_year    INT64,
  invoice_month   INT64,
  -- Synthetic partition column (derived from invoice_year, invoice_month; day=1)
  invoice_date    DATE
)
PARTITION BY invoice_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_loyalty_events: loyalty point earn/redeem
-- Source: PARTITIONED BY (event_date DATE)
-- BQ: PARTITION BY event_date (no clustering)
-- MAP<STRING,STRING> → JSON (meta)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_loyalty_events` (
  event_id   INT64,
  member_id  STRING,
  event_type STRING,       -- EARN / REDEEM / EXPIRE / ADJUST
  points     INT64,
  store_sk   INT64,
  tx_id      STRING,
  event_ts   TIMESTAMP,
  meta       JSON,         -- source: MAP<STRING,STRING>
  event_date DATE
)
PARTITION BY event_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_fraud_decisions: fraud-engine outcomes
-- Source: PARTITIONED BY (decision_date DATE)
-- BQ: PARTITION BY decision_date (no clustering)
-- DECIMAL(5,4) → NUMERIC (fraud_score)
-- ARRAY<STRING> (rule_signals)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_fraud_decisions` (
  txn_id        INT64,
  customer_sk   INT64,
  fraud_score   NUMERIC,    -- source: DECIMAL(5,4)
  decision      STRING,     -- APPROVE / REVIEW / DECLINE
  rule_signals  ARRAY<STRING>,
  decided_ts    TIMESTAMP,
  decision_date DATE
)
PARTITION BY decision_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_promo_redemptions: which promo applied to which order
-- Source: PARTITIONED BY (redemption_date DATE)
-- BQ: PARTITION BY redemption_date (no clustering)
-- DECIMAL(12,2) → NUMERIC (discount_amount)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_promo_redemptions` (
  redemption_id   INT64,
  promo_sk        INT64,
  invoice_no      STRING,
  customer_sk     INT64,
  discount_amount NUMERIC,    -- source: DECIMAL(12,2)
  applied_ts      TIMESTAMP,
  channel         STRING,
  redemption_date DATE
)
PARTITION BY redemption_date;

-- ────────────────────────────────────────────────────────────────────
-- fact_customer_complaints: ticketed complaints
-- Source: PARTITIONED BY (created_date DATE)
-- BQ: PARTITION BY created_date (no clustering)
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_customer_complaints` (
  complaint_id STRING,
  customer_sk  INT64,
  invoice_no   STRING,
  channel      STRING,
  severity     STRING,
  summary      STRING,
  created_at   TIMESTAMP,
  resolved_at  TIMESTAMP,
  csat_score   INT64,
  created_date DATE
)
PARTITION BY created_date;
