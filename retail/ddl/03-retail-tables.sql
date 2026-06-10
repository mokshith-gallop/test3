-- ============================================================================
-- 03-retail-tables.sql
-- BigQuery DDL for core retail dimensional warehouse tables.
-- Source: 03-retail-tables.hql (dims + fact_sales + fact_web_session)
--         08-rollup-etl.hql   (sales_cube + top_countries_daily)
--
-- Type mappings applied:
--   BIGINT       → INT64
--   INT          → INT64
--   TINYINT      → INT64   (widening 8→64 bit)
--   SMALLINT     → INT64   (widening 16→64 bit)
--   STRING       → STRING
--   DATE         → DATE
--   TIMESTAMP    → TIMESTAMP
--   DECIMAL(p,s) → NUMERIC
--   BOOLEAN      → BOOL
--
-- Hive-specific directives stripped:
--   STORED AS PARQUET/ORC, TBLPROPERTIES, CLUSTERED BY ... INTO N BUCKETS
--
-- Partitioning & clustering converted per locked strategy:
--   fact_sales:       PARTITION BY sale_date, CLUSTER BY customer_sk
--   fact_web_session: PARTITION BY event_date, CLUSTER BY country
--                     (country retained as regular column, moved from partition)
--   sales_cube:       PARTITION BY as_of_date
--   top_countries_daily: no partition/cluster (small daily snapshot)
-- ============================================================================

-- ---------------------------------------------------------------
-- Dimensions
-- ---------------------------------------------------------------

-- dim_date: date dimension (TPC-DS inspired)
CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_date` (
  d_date_sk           INT64,
  d_date_id           STRING,
  d_date              DATE,
  d_month_seq         INT64,
  d_week_seq          INT64,
  d_quarter_seq       INT64,
  d_year              INT64,
  d_dow               INT64,
  d_moy               INT64,
  d_dom               INT64,
  d_qoy               INT64,
  d_fy_year           INT64,
  d_fy_quarter_seq    INT64,
  d_day_name          STRING,
  d_holiday           STRING,
  d_weekend           STRING,
  d_following_holiday STRING,
  d_first_dom         INT64,
  d_last_dom          INT64,
  d_same_day_ly       INT64,
  d_same_day_lq       INT64,
  d_current_day       STRING,
  d_current_week      STRING,
  d_current_month     STRING,
  d_current_quarter   STRING,
  d_current_year      STRING
);

-- dim_customer: customer dimension
CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_customer` (
  customer_sk   INT64,
  customer_id   STRING,
  country       STRING,
  first_seen_ts TIMESTAMP,
  last_seen_ts  TIMESTAMP
);

-- dim_product: product dimension
CREATE OR REPLACE TABLE `acme-analytics-project.retail.dim_product` (
  product_sk  INT64,
  stock_code  STRING,
  description STRING,
  unit_price  NUMERIC   -- source: DECIMAL(10,2)
);

-- ---------------------------------------------------------------
-- Fact: line-item sales, partitioned by sale date
-- Source: PARTITIONED BY (sale_date DATE) CLUSTERED BY (customer_sk) INTO 8 BUCKETS
-- BQ:    PARTITION BY sale_date, CLUSTER BY customer_sk
-- ---------------------------------------------------------------

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_sales` (
  invoice_no  STRING,
  customer_sk INT64,
  product_sk  INT64,
  quantity    INT64,
  unit_price  NUMERIC,    -- source: DECIMAL(10,2)
  line_total  NUMERIC,    -- source: DECIMAL(14,2)
  country     STRING,
  invoice_ts  TIMESTAMP,
  sale_date   DATE
)
PARTITION BY sale_date
CLUSTER BY customer_sk;

-- ---------------------------------------------------------------
-- Fact: web sessions
-- Source: PARTITIONED BY (event_date DATE, country STRING)
-- BQ:    PARTITION BY event_date, CLUSTER BY country
--        country retained as regular column for backward compat
-- ---------------------------------------------------------------

CREATE OR REPLACE TABLE `acme-analytics-project.retail.fact_web_session` (
  event_ts   TIMESTAMP,
  ip         STRING,
  url        STRING,
  user_id    STRING,
  city       STRING,
  state      STRING,
  event_date DATE,
  country    STRING
)
PARTITION BY event_date
CLUSTER BY country;

-- ---------------------------------------------------------------
-- Rollup: executive daily dashboard cube
-- Source: 08-rollup-etl.hql
-- PARTITIONED BY (as_of_date DATE)
-- BQ: PARTITION BY as_of_date
-- TINYINT → INT64 (dim_level), SMALLINT → INT64 (month_key)
-- ---------------------------------------------------------------

CREATE OR REPLACE TABLE `acme-analytics-project.retail.sales_cube` (
  dim_level  INT64,      -- source: TINYINT (0=total,1=country,2=country+month,3=product)
  cube_key   STRING,
  country    STRING,
  month_key  INT64,      -- source: SMALLINT (yyyymm)
  product_sk INT64,
  orders     INT64,
  revenue    NUMERIC,    -- source: DECIMAL(18,2)
  units      INT64,
  as_of_date DATE
)
PARTITION BY as_of_date;

-- ---------------------------------------------------------------
-- Rollup: top countries daily snapshot
-- Source: 08-rollup-etl.hql
-- No partition/cluster (small daily snapshot table)
-- TINYINT → INT64 (rank)
-- ---------------------------------------------------------------

CREATE OR REPLACE TABLE `acme-analytics-project.retail.top_countries_daily` (
  as_of_date DATE,
  country    STRING,
  orders     INT64,
  revenue    NUMERIC,    -- source: DECIMAL(18,2)
  rank       INT64       -- source: TINYINT
);
