-- ============================================================================
-- 14-kudu-realtime.sql
-- BigQuery DDL for Kudu real-time tables, converted per locked kudu_realtime_strategy.
-- Source: 14-kudu-realtime.hql
--
-- Kudu conversion strategy:
--   kudu_inventory_realtime → Bigtable schema + BQ external table (CLOUD_BIGTABLE)
--   kudu_session_state      → BQ native table with CLUSTER BY session_id
--   kudu_promo_eligibility  → Bigtable schema only (no BQ table)
--   kudu_realtime_price     → Bigtable schema + BQ external table (CLOUD_BIGTABLE)
--
-- Type mappings applied:
--   STRING       → STRING
--   INT          → INT64
--   BIGINT (epoch millis) → TIMESTAMP (in BQ native tables)
--   BOOLEAN      → BOOL
--   DECIMAL(p,s) → NUMERIC
--
-- Kudu-specific syntax stripped:
--   PRIMARY KEY, PARTITION BY HASH, STORED AS KUDU, TBLPROPERTIES (kudu.*)
--   UPSERT statements not included (belong in ETL/pipeline code)
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════
-- kudu_inventory_realtime: live on-hand inventory per warehouse+sku
-- Target: Bigtable + BigQuery external table
-- Source: PRIMARY KEY (warehouse_id, sku)
-- Bigtable row key: warehouse_id#sku
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────
-- Bigtable schema (cbt commands — execute via Cloud Shell / gcloud CLI)
-- ────────────────────────────────────────────────────────────────────
-- cbt createtable kudu_inventory_realtime
-- cbt createfamily kudu_inventory_realtime inv
--
-- Column family "inv" stores:
--   inv:on_hand         (INT)
--   inv:allocated       (INT)
--   inv:available       (INT)
--   inv:last_updated_ts (BIGINT → epoch millis)
--
-- Row key format: <warehouse_id>#<sku>
-- Example: wh001#SKU-12345
-- ────────────────────────────────────────────────────────────────────

-- BigQuery external table for federated query over Bigtable
CREATE OR REPLACE EXTERNAL TABLE `acme-analytics-project.retail.kudu_inventory_realtime`
OPTIONS (
  format = 'CLOUD_BIGTABLE',
  uris = ['https://googleapis.com/bigtable/projects/acme-analytics-project/instances/retail-realtime/tables/kudu_inventory_realtime'],
  bigtable_options = '''{
    "readRowkeyAsString": true,
    "columnFamilies": [
      {
        "familyId": "inv",
        "onlyReadLatest": true,
        "columns": [
          {"qualifierString": "on_hand",         "type": "INTEGER"},
          {"qualifierString": "allocated",       "type": "INTEGER"},
          {"qualifierString": "available",       "type": "INTEGER"},
          {"qualifierString": "last_updated_ts", "type": "INTEGER"}
        ]
      }
    ]
  }'''
);


-- ════════════════════════════════════════════════════════════════════
-- kudu_session_state: live web/app session state
-- Target: BigQuery native table
-- Source: PRIMARY KEY (session_id)
-- BQ: CLUSTER BY session_id
-- BIGINT timestamp columns (started_ts, last_event_ts) → TIMESTAMP
-- AC #8: BigQuery native table with CLUSTER BY session_id
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE `acme-analytics-project.retail.kudu_session_state` (
  session_id     STRING,
  user_id        STRING,
  started_ts     TIMESTAMP,    -- source: BIGINT (epoch millis) → TIMESTAMP
  last_event_ts  TIMESTAMP,    -- source: BIGINT (epoch millis) → TIMESTAMP
  cart_value     NUMERIC,      -- source: DECIMAL(12,2)
  cart_items     INT64,
  current_screen STRING,
  platform       STRING,
  geo_country    STRING
)
CLUSTER BY session_id;


-- ════════════════════════════════════════════════════════════════════
-- kudu_promo_eligibility: per-customer promo eligibility state
-- Target: Bigtable only (no BQ external table)
-- Source: PRIMARY KEY (customer_id, promo_id)
-- Bigtable row key: customer_id#promo_id
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────
-- Bigtable schema (cbt commands — execute via Cloud Shell / gcloud CLI)
-- ────────────────────────────────────────────────────────────────────
-- cbt createtable kudu_promo_eligibility
-- cbt createfamily kudu_promo_eligibility elig
--
-- Column family "elig" stores:
--   elig:eligible            (BOOLEAN → stored as string "true"/"false")
--   elig:eligibility_reason  (STRING)
--   elig:valid_from_ts       (BIGINT → epoch millis)
--   elig:valid_to_ts         (BIGINT → epoch millis)
--   elig:redeemed            (BOOLEAN → stored as string "true"/"false")
--
-- Row key format: <customer_id>#<promo_id>
-- Example: CUST-001#PROMO-SPRING2024
-- ────────────────────────────────────────────────────────────────────


-- ════════════════════════════════════════════════════════════════════
-- kudu_realtime_price: live SKU pricing (margin-driven re-pricing engine)
-- Target: Bigtable + BigQuery external table
-- Source: PRIMARY KEY (sku, store_id)
-- Bigtable row key: sku#store_id
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────
-- Bigtable schema (cbt commands — execute via Cloud Shell / gcloud CLI)
-- ────────────────────────────────────────────────────────────────────
-- cbt createtable kudu_realtime_price
-- cbt createfamily kudu_realtime_price pricing
--
-- Column family "pricing" stores:
--   pricing:price          (DECIMAL → stored as string)
--   pricing:list_price     (DECIMAL → stored as string)
--   pricing:cost           (DECIMAL → stored as string)
--   pricing:margin_pct     (DECIMAL → stored as string)
--   pricing:updated_ts     (BIGINT → epoch millis)
--   pricing:pricing_engine (STRING)
--
-- Row key format: <sku>#<store_id>
-- Example: SKU-12345#STORE-001
-- ────────────────────────────────────────────────────────────────────

-- BigQuery external table for federated query over Bigtable
CREATE OR REPLACE EXTERNAL TABLE `acme-analytics-project.retail.kudu_realtime_price`
OPTIONS (
  format = 'CLOUD_BIGTABLE',
  uris = ['https://googleapis.com/bigtable/projects/acme-analytics-project/instances/retail-realtime/tables/kudu_realtime_price'],
  bigtable_options = '''{
    "readRowkeyAsString": true,
    "columnFamilies": [
      {
        "familyId": "pricing",
        "onlyReadLatest": true,
        "columns": [
          {"qualifierString": "price",          "type": "STRING"},
          {"qualifierString": "list_price",     "type": "STRING"},
          {"qualifierString": "cost",           "type": "STRING"},
          {"qualifierString": "margin_pct",     "type": "STRING"},
          {"qualifierString": "updated_ts",     "type": "INTEGER"},
          {"qualifierString": "pricing_engine", "type": "STRING"}
        ]
      }
    ]
  }'''
);
