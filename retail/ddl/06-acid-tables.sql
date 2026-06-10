-- ============================================================================
-- 06-acid-tables.sql
-- BigQuery DDL for Hive ACID tables converted to native BigQuery tables.
-- Source: 06-acid-tables.hql
--
-- Conversion notes:
--   - Hive ACID properties stripped (transactional=true, transactional_properties,
--     orc.compress, bucketing_version). BigQuery is natively ACID — no special
--     table properties required for UPDATE/DELETE/MERGE support.
--   - STORED AS ORC → dropped (BigQuery manages Capacitor format internally)
--   - CLUSTERED BY (return_id) INTO 4 BUCKETS → CLUSTER BY return_id
--   - Hive DML statements (UPDATE, DELETE, MERGE) are NOT included here;
--     they belong in ETL/pipeline code, not in DDL.
--
-- AC #7: returns_ledger is a native BigQuery table, no transactional
--        properties, CLUSTER BY return_id.
-- ============================================================================

-- ---------------------------------------------------------------
-- returns_ledger: late-binding corrections by customer service.
-- Source: Hive ACID ORC, CLUSTERED BY (return_id) INTO 4 BUCKETS
-- BQ: native table, CLUSTER BY return_id
-- ---------------------------------------------------------------

CREATE OR REPLACE TABLE `acme-analytics-project.retail.returns_ledger` (
  return_id     INT64,
  invoice_no    STRING,
  customer_sk   INT64,
  return_ts     TIMESTAMP,
  refund_amount NUMERIC,    -- source: DECIMAL(12,2)
  reason_code   STRING,
  status        STRING
)
CLUSTER BY return_id;
