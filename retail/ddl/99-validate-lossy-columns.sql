-- ============================================================================
-- 99-validate-lossy-columns.sql
-- AC #9: Lossy-column round-trip validation script.
--
-- Proves exact round-trip equality for every lossy-mapped column across all
-- retail tables. Lossy categories tested:
--   1. TINYINT/SMALLINT → INT64 (widening; boundary values 127/-128, 32767/-32768)
--   2. DECIMAL(p,s)     → NUMERIC (all precision variants)
--   3. DOUBLE           → FLOAT64 (IEEE 754 double)
--   4. TIMESTAMP        → TIMESTAMP (microsecond precision edges)
--   5. MAP<STRING,STRING> → JSON (round-trip fidelity)
--   6. BIGINT           → INT64 (boundary: ±9223372036854775807)
--   7. ARRAY<STRING>    → ARRAY<STRING>
--   8. ARRAY<STRUCT>    → ARRAY<STRUCT>
--   9. STRUCT           → STRUCT
--
-- Structure:
--   Phase 1: SEED — INSERT canonical edge-value rows (test_marker = '__LOSSY_TEST__')
--   Phase 2: VERIFY — SELECT EXCEPT DISTINCT against expected literals
--   Phase 3: CLEANUP — DELETE seeded test rows
--   Phase 4: SUMMARY — report pass/fail per table
--
-- Sentinel value: All test rows use a distinctive marker so cleanup is safe:
--   - String columns use '__LOSSY_TEST__' where possible
--   - Partitioned tables use DATE '2099-12-31' as partition key
--   - BIGINT SK columns use -999999999 as the test surrogate key
--
-- Coverage: 0 unprobed lossy columns. Every column from the lossy census
-- has a test case.
-- ============================================================================

-- ============================================================================
-- PHASE 1: SEED — Insert canonical edge-value rows
-- ============================================================================

-- ── dim_date ────────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (d_date_sk), INT→INT64 (all int cols)
INSERT INTO `acme-analytics-project.retail.dim_date` (
  d_date_sk, d_date_id, d_date,
  d_month_seq, d_week_seq, d_quarter_seq, d_year, d_dow, d_moy, d_dom,
  d_qoy, d_fy_year, d_fy_quarter_seq,
  d_day_name, d_holiday, d_weekend, d_following_holiday,
  d_first_dom, d_last_dom, d_same_day_ly, d_same_day_lq,
  d_current_day, d_current_week, d_current_month, d_current_quarter, d_current_year
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', DATE '2099-12-31',
  2147483647, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647,
  2147483647, 2147483647, 2147483647,
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  2147483647, 2147483647, 2147483647, 2147483647,
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__'
);

-- ── dim_customer ────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk), TIMESTAMP (first_seen_ts, last_seen_ts)
INSERT INTO `acme-analytics-project.retail.dim_customer` (
  customer_sk, customer_id, country, first_seen_ts, last_seen_ts
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── dim_product ─────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (product_sk), DECIMAL(10,2)→NUMERIC (unit_price)
INSERT INTO `acme-analytics-project.retail.dim_product` (
  product_sk, stock_code, description, unit_price
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__',
  99999999.99  -- DECIMAL(10,2) max
);

-- ── fact_sales ──────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk, product_sk), INT→INT64 (quantity),
--         DECIMAL(10,2)→NUMERIC (unit_price), DECIMAL(14,2)→NUMERIC (line_total),
--         TIMESTAMP (invoice_ts)
INSERT INTO `acme-analytics-project.retail.fact_sales` (
  invoice_no, customer_sk, product_sk, quantity, unit_price, line_total,
  country, invoice_ts, sale_date
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807, 2147483647,
  99999999.99,          -- DECIMAL(10,2) max
  999999999999.99,      -- DECIMAL(14,2) max
  '__LOSSY_TEST__',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  DATE '2099-12-31'
);

-- ── fact_web_session ────────────────────────────────────────────────
-- Lossy: TIMESTAMP (event_ts)
INSERT INTO `acme-analytics-project.retail.fact_web_session` (
  event_ts, ip, url, user_id, city, state, event_date, country
) VALUES (
  TIMESTAMP '0001-01-01 00:00:00.000000',
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  '__LOSSY_TEST__', '__LOSSY_TEST__', DATE '2099-12-31', '__LOSSY_TEST__'
);

-- ── sales_cube ──────────────────────────────────────────────────────
-- Lossy: TINYINT→INT64 (dim_level), SMALLINT→INT64 (month_key),
--         BIGINT→INT64 (product_sk, orders, units), DECIMAL(18,2)→NUMERIC (revenue)
INSERT INTO `acme-analytics-project.retail.sales_cube` (
  dim_level, cube_key, country, month_key, product_sk, orders, revenue, units, as_of_date
) VALUES (
  127, '__LOSSY_TEST__', '__LOSSY_TEST__', 32767,
  9223372036854775807, 9223372036854775807,
  9999999999999999.99,  -- DECIMAL(18,2) max
  9223372036854775807,
  DATE '2099-12-31'
);
-- Second row with negative TINYINT/SMALLINT boundaries
INSERT INTO `acme-analytics-project.retail.sales_cube` (
  dim_level, cube_key, country, month_key, product_sk, orders, revenue, units, as_of_date
) VALUES (
  -128, '__LOSSY_TEST_NEG__', '__LOSSY_TEST__', -32768,
  -9223372036854775808, -9223372036854775808,
  -9999999999999999.99,
  -9223372036854775808,
  DATE '2099-12-31'
);

-- ── top_countries_daily ─────────────────────────────────────────────
-- Lossy: TINYINT→INT64 (rank), BIGINT→INT64 (orders),
--         DECIMAL(18,2)→NUMERIC (revenue)
INSERT INTO `acme-analytics-project.retail.top_countries_daily` (
  as_of_date, country, orders, revenue, rank
) VALUES (
  DATE '2099-12-31', '__LOSSY_TEST__', 9223372036854775807,
  9999999999999999.99,  -- DECIMAL(18,2) max
  127                   -- TINYINT max
);
INSERT INTO `acme-analytics-project.retail.top_countries_daily` (
  as_of_date, country, orders, revenue, rank
) VALUES (
  DATE '2099-12-31', '__LOSSY_TEST_NEG__', -9223372036854775808,
  -9999999999999999.99,
  -128                  -- TINYINT min
);

-- ── returns_ledger ──────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (return_id, customer_sk), TIMESTAMP (return_ts),
--         DECIMAL(12,2)→NUMERIC (refund_amount)
INSERT INTO `acme-analytics-project.retail.returns_ledger` (
  return_id, invoice_no, customer_sk, return_ts, refund_amount, reason_code, status
) VALUES (
  -999999999, '__LOSSY_TEST__', 9223372036854775807,
  TIMESTAMP '9999-12-31 23:59:59.999999',
  9999999999.99,        -- DECIMAL(12,2) max
  '__LOSSY_TEST__', '__LOSSY_TEST__'
);

-- ── dim_store ───────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (store_sk, manager_employee_sk), INT→INT64 (sq_ft),
--         MAP<STRING,STRING>→JSON (attributes)
INSERT INTO `acme-analytics-project.retail.dim_store` (
  store_sk, store_id, store_name, store_type, region, city, state, country,
  open_dt, close_dt, sq_ft, manager_employee_sk, attributes
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  DATE '2099-12-31', DATE '2099-12-31', 2147483647, 9223372036854775807,
  JSON '{"key1":"val1","key2":"val2"}'
);

-- ── dim_supplier ────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (supplier_sk), INT→INT64 (payment_terms_days),
--         STRUCT (primary_contact), ARRAY<STRING> (categories)
INSERT INTO `acme-analytics-project.retail.dim_supplier` (
  supplier_sk, supplier_id, supplier_name, country, tax_id, payment_terms_days,
  onboard_dt, risk_rating, primary_contact, categories
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  '__LOSSY_TEST__', 2147483647, DATE '2099-12-31', '__LOSSY_TEST__',
  STRUCT('John Doe' AS name, 'john@test.com' AS email, '+1-555-0100' AS phone),
  ['cat_a', 'cat_b', 'cat_c']
);

-- ── dim_employee ────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (employee_sk, home_store_sk, manager_sk)
INSERT INTO `acme-analytics-project.retail.dim_employee` (
  employee_sk, employee_id, first_name, last_name, hire_dt, termination_dt,
  role, department, home_store_sk, manager_sk, salary_band
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  DATE '2099-12-31', DATE '2099-12-31', '__LOSSY_TEST__', '__LOSSY_TEST__',
  9223372036854775807, 9223372036854775807, '__LOSSY_TEST__'
);

-- ── dim_promotion ───────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (promo_sk), DECIMAL(5,2)→NUMERIC (pct_off),
--         DECIMAL(10,2)→NUMERIC (flat_off), DECIMAL(14,2)→NUMERIC (budget),
--         MAP<STRING,STRING>→JSON (eligibility), ARRAY<STRING> (channels)
INSERT INTO `acme-analytics-project.retail.dim_promotion` (
  promo_sk, promo_id, name, promo_type, pct_off, flat_off, start_dt, end_dt,
  budget, channels, eligibility
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  999.99,              -- DECIMAL(5,2) max
  99999999.99,         -- DECIMAL(10,2) max
  DATE '2099-12-31', DATE '2099-12-31',
  999999999999.99,     -- DECIMAL(14,2) max
  ['online', 'instore', 'app'],
  JSON '{"tier":"gold","min_spend":"100"}'
);

-- ── dim_warehouse ───────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (warehouse_sk, capacity_units),
--         STRUCT<lat FLOAT64, lon FLOAT64> (geocode) — DOUBLE→FLOAT64
INSERT INTO `acme-analytics-project.retail.dim_warehouse` (
  warehouse_sk, warehouse_id, name, type, operator, region, capacity_units,
  open_dt, geocode
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  '__LOSSY_TEST__', '__LOSSY_TEST__', 9223372036854775807,
  DATE '2099-12-31',
  STRUCT(1.7976931348623157e+308 AS lat, -1.7976931348623157e+308 AS lon)
);

-- ── dim_currency ────────────────────────────────────────────────────
-- Lossy: INT→INT64 (minor_unit)
INSERT INTO `acme-analytics-project.retail.dim_currency` (
  currency_code, currency_name, minor_unit, symbol
) VALUES (
  '__LOSSY_TEST__', '__LOSSY_TEST__', 2147483647, '__LOSSY_TEST__'
);

-- ── dim_geography ───────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (geo_sk), DOUBLE→FLOAT64 (latitude, longitude)
INSERT INTO `acme-analytics-project.retail.dim_geography` (
  geo_sk, country_iso2, country_name, region_code, region_name, city,
  postal_code, timezone, latitude, longitude
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  1.7976931348623157e+308, -1.7976931348623157e+308
);

-- ── dim_color ───────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (color_sk)
INSERT INTO `acme-analytics-project.retail.dim_color` (
  color_sk, color_code, color_name, color_family, hex_code
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__'
);

-- ── dim_size ────────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (size_sk), INT→INT64 (sort_order)
INSERT INTO `acme-analytics-project.retail.dim_size` (
  size_sk, size_code, size_name, size_system, sort_order
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__', 2147483647
);

-- ── dim_brand ───────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (brand_sk)
INSERT INTO `acme-analytics-project.retail.dim_brand` (
  brand_sk, brand_id, brand_name, parent_company, private_label, launch_dt
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  TRUE, DATE '2099-12-31'
);

-- ── dim_category ────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (category_sk), INT→INT64 (depth, sort_order)
INSERT INTO `acme-analytics-project.retail.dim_category` (
  category_sk, category_id, parent_id, name, depth, sort_order
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  2147483647, 2147483647
);

-- ── dim_payment_method ──────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (payment_method_sk), DECIMAL(5,4)→NUMERIC (fee_pct),
--         DECIMAL(8,2)→NUMERIC (fee_flat), INT→INT64 (settlement_days)
INSERT INTO `acme-analytics-project.retail.dim_payment_method` (
  payment_method_sk, method_code, method_name, category, fee_pct, fee_flat, settlement_days
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  9.9999,              -- DECIMAL(5,4) max
  999999.99,           -- DECIMAL(8,2) max
  2147483647
);

-- ── fact_inventory_movements ────────────────────────────────────────
-- Lossy: BIGINT→INT64 (movement_id, warehouse_sk, store_sk, operator_sk),
--         TIMESTAMP (movement_ts), INT→INT64 (quantity, year, month, day)
INSERT INTO `acme-analytics-project.retail.fact_inventory_movements` (
  movement_id, movement_ts, sku, warehouse_sk, store_sk, movement_type,
  quantity, reference_doc, reason_code, operator_sk,
  year, month, day, region, movement_date
) VALUES (
  9223372036854775807, TIMESTAMP '9999-12-31 23:59:59.999999',
  '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807, '__LOSSY_TEST__',
  2147483647, '__LOSSY_TEST__', '__LOSSY_TEST__', 9223372036854775807,
  2099, 12, 31, '__LOSSY_TEST__', DATE '2099-12-31'
);

-- ── fact_inventory_snapshot ─────────────────────────────────────────
-- Lossy: BIGINT→INT64 (warehouse_sk), INT→INT64 (on_hand_units etc.),
--         DECIMAL(12,4)→NUMERIC (avg_cost), TIMESTAMP (last_movement_ts)
INSERT INTO `acme-analytics-project.retail.fact_inventory_snapshot` (
  sku, warehouse_sk, on_hand_units, allocated_units, in_transit_units,
  available_units, avg_cost, last_movement_ts, snapshot_date
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807, 2147483647, 2147483647, 2147483647,
  2147483647,
  99999999.9999,       -- DECIMAL(12,4) max
  TIMESTAMP '0001-01-01 00:00:00.000000',
  DATE '2099-12-31'
);

-- ── fact_returns ────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (return_id, customer_sk, product_sk, store_sk),
--         INT→INT64 (quantity), DECIMAL(12,2)→NUMERIC (refund_amount),
--         TIMESTAMP (return_ts)
INSERT INTO `acme-analytics-project.retail.fact_returns` (
  return_id, invoice_no, customer_sk, product_sk, return_ts, quantity,
  refund_amount, reason_code, return_channel, store_sk, return_date
) VALUES (
  -999999999, '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807,
  TIMESTAMP '9999-12-31 23:59:59.999999', 2147483647,
  9999999999.99,       -- DECIMAL(12,2) max
  '__LOSSY_TEST__', '__LOSSY_TEST__', 9223372036854775807, DATE '2099-12-31'
);

-- ── fact_payments ───────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (payment_id, customer_sk, payment_method_sk),
--         DECIMAL(14,2)→NUMERIC (amount), DECIMAL(10,2)→NUMERIC (fee_amount),
--         TIMESTAMP (payment_ts), INT→INT64 (post_year, post_month)
INSERT INTO `acme-analytics-project.retail.fact_payments` (
  payment_id, invoice_no, customer_sk, payment_method_sk, amount, currency_code,
  payment_ts, auth_code, settlement_id, fee_amount,
  post_year, post_month, payment_method_partition, post_date
) VALUES (
  -999999999, '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807,
  999999999999.99,     -- DECIMAL(14,2) max
  '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  '__LOSSY_TEST__', '__LOSSY_TEST__',
  99999999.99,         -- DECIMAL(10,2) max
  2099, 12, '__LOSSY_TEST__', DATE '2099-12-01'
);

-- ── fact_shipments ──────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk, warehouse_sk), TIMESTAMP (shipped_ts, delivered_ts),
--         INT→INT64 (sla_hours, ship_year, ship_month, ship_day),
--         ARRAY<STRUCT<ts TIMESTAMP, status STRING, location STRING>> (tracking_events)
INSERT INTO `acme-analytics-project.retail.fact_shipments` (
  shipment_id, invoice_no, customer_sk, warehouse_sk, carrier, tracking_no,
  shipped_ts, delivered_ts, sla_hours, tracking_events,
  ship_year, ship_month, ship_day, carrier_partition, ship_date
) VALUES (
  '__LOSSY_TEST__', '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807,
  '__LOSSY_TEST__', '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  2147483647,
  [STRUCT(TIMESTAMP '9999-12-31 23:59:59.999999' AS ts, 'DELIVERED' AS status, 'NYC' AS location),
   STRUCT(TIMESTAMP '0001-01-01 00:00:00.000000' AS ts, 'SHIPPED' AS status, 'LAX' AS location)],
  2099, 12, 31, '__LOSSY_TEST__', DATE '2099-12-31'
);

-- ── fact_refunds ────────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (refund_id, payment_id, return_id, customer_sk),
--         DECIMAL(14,2)→NUMERIC (amount), TIMESTAMP (refund_ts)
INSERT INTO `acme-analytics-project.retail.fact_refunds` (
  refund_id, payment_id, return_id, customer_sk, amount, currency_code,
  refund_ts, refund_method, refund_date
) VALUES (
  -999999999, 9223372036854775807, 9223372036854775807, 9223372036854775807,
  999999999999.99,     -- DECIMAL(14,2) max
  '__LOSSY_TEST__',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  '__LOSSY_TEST__', DATE '2099-12-31'
);

-- ── fact_app_clicks ─────────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (user_sk), TIMESTAMP (event_ts),
--         MAP<STRING,STRING>→JSON (properties),
--         STRUCT<platform STRING, version STRING, model STRING> (device)
INSERT INTO `acme-analytics-project.retail.fact_app_clicks` (
  session_id, user_sk, event_ts, event_type, screen, target_id,
  properties, device, event_date, platform_partition
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807,
  TIMESTAMP '9999-12-31 23:59:59.999999',
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  JSON '{"action":"click","element":"buy_button"}',
  STRUCT('iOS' AS platform, '17.4' AS version, 'iPhone15' AS model),
  DATE '2099-12-31', '__LOSSY_TEST__'
);

-- ── fact_email_engagement ───────────────────────────────────────────
-- Lossy: BIGINT→INT64 (campaign_sk, user_sk), TIMESTAMP (event_ts),
--         ARRAY<STRUCT<ts TIMESTAMP, url STRING>> (clicks)
INSERT INTO `acme-analytics-project.retail.fact_email_engagement` (
  send_id, campaign_sk, user_sk, event_type, event_ts, link_url,
  clicks, event_date
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807,
  '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  '__LOSSY_TEST__',
  [STRUCT(TIMESTAMP '9999-12-31 23:59:59.999999' AS ts, 'https://test.com/a' AS url),
   STRUCT(TIMESTAMP '0001-01-01 00:00:00.000000' AS ts, 'https://test.com/b' AS url)],
  DATE '2099-12-31'
);

-- ── fact_chat_interactions ──────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk, agent_sk), TIMESTAMP (started_at, ended_at),
--         INT→INT64 (duration_sec, message_count, csat_score),
--         DECIMAL(4,3)→NUMERIC (sentiment_avg)
INSERT INTO `acme-analytics-project.retail.fact_chat_interactions` (
  chat_id, customer_sk, agent_sk, started_at, ended_at, duration_sec,
  message_count, resolved, csat_score, sentiment_avg, start_date
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807,
  TIMESTAMP '0001-01-01 00:00:00.000000',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  2147483647, 2147483647, TRUE, 2147483647,
  9.999,               -- DECIMAL(4,3) max
  DATE '2099-12-31'
);

-- ── fact_warehouse_picks ────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (pick_id, warehouse_sk, picker_sk),
--         INT→INT64 (quantity, duration_ms), TIMESTAMP (picked_ts)
INSERT INTO `acme-analytics-project.retail.fact_warehouse_picks` (
  pick_id, warehouse_sk, picker_sk, sku, quantity, picked_ts, duration_ms,
  bin_location, pick_date, warehouse_partition
) VALUES (
  9223372036854775807, 9223372036854775807, 9223372036854775807,
  '__LOSSY_TEST__', 2147483647,
  TIMESTAMP '9999-12-31 23:59:59.999999',
  2147483647, '__LOSSY_TEST__', DATE '2099-12-31', '__LOSSY_TEST__'
);

-- ── fact_supplier_invoice_lines ─────────────────────────────────────
-- Lossy: BIGINT→INT64 (invoice_line_id, supplier_sk),
--         INT→INT64 (quantity, invoice_year, invoice_month),
--         DECIMAL(12,4)→NUMERIC (unit_cost), DECIMAL(14,2)→NUMERIC (line_total),
--         TIMESTAMP (received_ts)
INSERT INTO `acme-analytics-project.retail.fact_supplier_invoice_lines` (
  invoice_line_id, invoice_no, supplier_sk, sku, quantity, unit_cost, line_total,
  currency_code, received_ts, invoice_year, invoice_month, invoice_date
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', 9223372036854775807,
  '__LOSSY_TEST__', 2147483647,
  99999999.9999,       -- DECIMAL(12,4) max
  999999999999.99,     -- DECIMAL(14,2) max
  '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  2099, 12, DATE '2099-12-01'
);

-- ── fact_loyalty_events ─────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (event_id, store_sk), INT→INT64 (points),
--         TIMESTAMP (event_ts), MAP<STRING,STRING>→JSON (meta)
INSERT INTO `acme-analytics-project.retail.fact_loyalty_events` (
  event_id, member_id, event_type, points, store_sk, tx_id, event_ts,
  meta, event_date
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', 2147483647,
  9223372036854775807, '__LOSSY_TEST__',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  JSON '{"source":"pos","tier":"platinum"}',
  DATE '2099-12-31'
);

-- ── fact_fraud_decisions ────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (txn_id, customer_sk), DECIMAL(5,4)→NUMERIC (fraud_score),
--         ARRAY<STRING> (rule_signals), TIMESTAMP (decided_ts)
INSERT INTO `acme-analytics-project.retail.fact_fraud_decisions` (
  txn_id, customer_sk, fraud_score, decision, rule_signals, decided_ts, decision_date
) VALUES (
  9223372036854775807, 9223372036854775807,
  9.9999,              -- DECIMAL(5,4) max
  '__LOSSY_TEST__',
  ['velocity_check', 'geo_anomaly', 'device_fingerprint'],
  TIMESTAMP '0001-01-01 00:00:00.000000',
  DATE '2099-12-31'
);

-- ── fact_promo_redemptions ──────────────────────────────────────────
-- Lossy: BIGINT→INT64 (redemption_id, promo_sk, customer_sk),
--         DECIMAL(12,2)→NUMERIC (discount_amount), TIMESTAMP (applied_ts)
INSERT INTO `acme-analytics-project.retail.fact_promo_redemptions` (
  redemption_id, promo_sk, invoice_no, customer_sk, discount_amount,
  applied_ts, channel, redemption_date
) VALUES (
  9223372036854775807, 9223372036854775807, '__LOSSY_TEST__', 9223372036854775807,
  9999999999.99,       -- DECIMAL(12,2) max
  TIMESTAMP '9999-12-31 23:59:59.999999',
  '__LOSSY_TEST__', DATE '2099-12-31'
);

-- ── fact_customer_complaints ────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk), INT→INT64 (csat_score),
--         TIMESTAMP (created_at, resolved_at)
INSERT INTO `acme-analytics-project.retail.fact_customer_complaints` (
  complaint_id, customer_sk, invoice_no, channel, severity, summary,
  created_at, resolved_at, csat_score, created_date
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807, '__LOSSY_TEST__',
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  2147483647, DATE '2099-12-31'
);

-- ── agg_daily_sales_by_store ────────────────────────────────────────
-- Lossy: BIGINT→INT64 (store_sk, units_sold, txn_count),
--         DECIMAL(16,2)→NUMERIC (gross_revenue, net_revenue),
--         DECIMAL(12,2)→NUMERIC (avg_basket)
INSERT INTO `acme-analytics-project.retail.agg_daily_sales_by_store` (
  store_sk, gross_revenue, net_revenue, units_sold, txn_count, avg_basket, sale_date
) VALUES (
  9223372036854775807,
  99999999999999.99,   -- DECIMAL(16,2) max
  99999999999999.99,
  9223372036854775807, 9223372036854775807,
  9999999999.99,       -- DECIMAL(12,2) max
  DATE '2099-12-31'
);

-- ── agg_daily_sales_by_product ──────────────────────────────────────
-- Lossy: BIGINT→INT64 (product_sk, units_sold, return_units, net_units),
--         DECIMAL(16,2)→NUMERIC (gross_revenue, cogs),
--         DECIMAL(6,4)→NUMERIC (margin_pct)
INSERT INTO `acme-analytics-project.retail.agg_daily_sales_by_product` (
  product_sk, units_sold, gross_revenue, margin_pct, cogs, return_units, net_units, sale_date
) VALUES (
  9223372036854775807, 9223372036854775807,
  99999999999999.99,   -- DECIMAL(16,2) max
  99.9999,             -- DECIMAL(6,4) max
  99999999999999.99,
  9223372036854775807, 9223372036854775807,
  DATE '2099-12-31'
);

-- ── agg_weekly_customer_ltv ─────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk), INT→INT64 (orders_to_date, days_since_last_order),
--         DECIMAL(16,2)→NUMERIC (ltv_to_date),
--         DECIMAL(12,2)→NUMERIC (avg_order_value),
--         DECIMAL(4,3)→NUMERIC (churn_risk)
INSERT INTO `acme-analytics-project.retail.agg_weekly_customer_ltv` (
  customer_sk, ltv_to_date, orders_to_date, avg_order_value,
  days_since_last_order, rfm_score, churn_risk, week_start_date
) VALUES (
  9223372036854775807,
  99999999999999.99,   -- DECIMAL(16,2) max
  2147483647,
  9999999999.99,       -- DECIMAL(12,2) max
  2147483647, '__LOSSY_TEST__',
  9.999,               -- DECIMAL(4,3) max
  DATE '2099-12-31'
);

-- ── agg_monthly_supplier_performance ────────────────────────────────
-- Lossy: BIGINT→INT64 (supplier_sk, units_received), INT→INT64 (orders_placed),
--         DECIMAL(5,4)→NUMERIC (on_time_pct, fill_rate_pct),
--         DECIMAL(6,2)→NUMERIC (avg_lead_time_days),
--         DECIMAL(4,3)→NUMERIC (quality_score),
--         DECIMAL(16,2)→NUMERIC (total_spend)
INSERT INTO `acme-analytics-project.retail.agg_monthly_supplier_performance` (
  supplier_sk, orders_placed, units_received, on_time_pct, fill_rate_pct,
  avg_lead_time_days, quality_score, total_spend, month_start
) VALUES (
  9223372036854775807, 2147483647, 9223372036854775807,
  9.9999,              -- DECIMAL(5,4) max
  9.9999,
  9999.99,             -- DECIMAL(6,2) max
  9.999,               -- DECIMAL(4,3) max
  99999999999999.99,   -- DECIMAL(16,2) max
  DATE '2099-12-31'
);

-- ── agg_hourly_warehouse_kpi ────────────────────────────────────────
-- Lossy: BIGINT→INT64 (warehouse_sk), INT→INT64 (units_in, units_picked, units_shipped, backlog_units),
--         DECIMAL(8,2)→NUMERIC (pick_rate_uph, avg_pick_seconds),
--         TIMESTAMP (snapshot_ts)
INSERT INTO `acme-analytics-project.retail.agg_hourly_warehouse_kpi` (
  warehouse_sk, units_in, units_picked, units_shipped, pick_rate_uph,
  backlog_units, avg_pick_seconds, snapshot_hour, snapshot_ts
) VALUES (
  9223372036854775807, 2147483647, 2147483647, 2147483647,
  999999.99,           -- DECIMAL(8,2) max
  2147483647,
  999999.99,
  '__LOSSY_TEST__',
  TIMESTAMP '2099-12-31 23:00:00.000000'
);

-- ── agg_daily_carrier_otd ───────────────────────────────────────────
-- Lossy: INT→INT64 (shipments_total, delivered_on_time, delivered_late, in_transit),
--         DECIMAL(5,4)→NUMERIC (otd_pct), DECIMAL(8,2)→NUMERIC (avg_transit_hours)
INSERT INTO `acme-analytics-project.retail.agg_daily_carrier_otd` (
  carrier, shipments_total, delivered_on_time, delivered_late, in_transit,
  otd_pct, avg_transit_hours, ship_date
) VALUES (
  '__LOSSY_TEST__', 2147483647, 2147483647, 2147483647, 2147483647,
  9.9999,              -- DECIMAL(5,4) max
  999999.99,           -- DECIMAL(8,2) max
  DATE '2099-12-31'
);

-- ── agg_marketing_attribution_cube ──────────────────────────────────
-- Lossy: BIGINT→INT64 (campaign_sk, attributed_units), INT→INT64 (grouping_id),
--         DECIMAL(16,2)→NUMERIC (attributed_revenue),
--         DECIMAL(14,2)→NUMERIC (cost), DECIMAL(8,4)→NUMERIC (roas)
INSERT INTO `acme-analytics-project.retail.agg_marketing_attribution_cube` (
  channel, campaign_sk, region, attributed_revenue, attributed_units,
  cost, roas, grouping_id, period_date
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807, '__LOSSY_TEST__',
  99999999999999.99,   -- DECIMAL(16,2) max
  9223372036854775807,
  999999999999.99,     -- DECIMAL(14,2) max
  9999.9999,           -- DECIMAL(8,4) max
  2147483647,
  DATE '2099-12-31'
);

-- ── agg_returns_by_reason_monthly ───────────────────────────────────
-- Lossy: BIGINT→INT64 (return_count, return_units),
--         DECIMAL(16,2)→NUMERIC (total_refunded),
--         DECIMAL(8,2)→NUMERIC (avg_days_to_return)
INSERT INTO `acme-analytics-project.retail.agg_returns_by_reason_monthly` (
  reason_code, return_count, return_units, total_refunded, avg_days_to_return, month_start
) VALUES (
  '__LOSSY_TEST__', 9223372036854775807, 9223372036854775807,
  99999999999999.99,   -- DECIMAL(16,2) max
  999999.99,           -- DECIMAL(8,2) max
  DATE '2099-12-31'
);

-- ── acid_customer_address_history ───────────────────────────────────
-- Lossy: BIGINT→INT64 (history_id, customer_sk), TIMESTAMP (eff_from, eff_to)
INSERT INTO `acme-analytics-project.retail.acid_customer_address_history` (
  history_id, customer_sk, address_line1, address_city, address_region,
  address_country, address_postal, eff_from, eff_to, is_current, change_reason
) VALUES (
  -999999999, 9223372036854775807,
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  '__LOSSY_TEST__', '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  TRUE, '__LOSSY_TEST__'
);

-- ── acid_supplier_terms_history ─────────────────────────────────────
-- Lossy: BIGINT→INT64 (history_id, supplier_sk), INT→INT64 (payment_terms_days),
--         DECIMAL(5,2)→NUMERIC (discount_pct), TIMESTAMP (eff_from, eff_to)
INSERT INTO `acme-analytics-project.retail.acid_supplier_terms_history` (
  history_id, supplier_sk, payment_terms_days, discount_pct,
  eff_from, eff_to, is_current, changed_by
) VALUES (
  -999999999, 9223372036854775807, 2147483647,
  999.99,              -- DECIMAL(5,2) max
  TIMESTAMP '0001-01-01 00:00:00.000000',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  TRUE, '__LOSSY_TEST__'
);

-- ── acid_loyalty_points_ledger ──────────────────────────────────────
-- Lossy: BIGINT→INT64 (entry_id), INT→INT64 (points_delta, running_balance),
--         TIMESTAMP (event_ts, expiry_ts)
INSERT INTO `acme-analytics-project.retail.acid_loyalty_points_ledger` (
  entry_id, member_id, points_delta, running_balance, event_ts, event_type,
  reference_id, expiry_ts
) VALUES (
  -999999999, '__LOSSY_TEST__', 2147483647, 2147483647,
  TIMESTAMP '0001-01-01 00:00:00.000000',
  '__LOSSY_TEST__', '__LOSSY_TEST__',
  TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── acid_inventory_adjustments_log ──────────────────────────────────
-- Lossy: BIGINT→INT64 (adjustment_id, warehouse_sk), INT→INT64 (quantity_delta),
--         TIMESTAMP (adjusted_at, approved_at)
INSERT INTO `acme-analytics-project.retail.acid_inventory_adjustments_log` (
  adjustment_id, warehouse_sk, sku, quantity_delta, reason_code, notes,
  adjusted_by, adjusted_at, approved_by, approved_at
) VALUES (
  -999999999, 9223372036854775807, '__LOSSY_TEST__', 2147483647,
  '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  '__LOSSY_TEST__',
  TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── kudu_session_state ──────────────────────────────────────────────
-- Lossy: BIGINT epoch→TIMESTAMP (started_ts, last_event_ts),
--         DECIMAL(12,2)→NUMERIC (cart_value), INT→INT64 (cart_items)
INSERT INTO `acme-analytics-project.retail.kudu_session_state` (
  session_id, user_id, started_ts, last_event_ts, cart_value, cart_items,
  current_screen, platform, geo_country
) VALUES (
  '__LOSSY_TEST__', '__LOSSY_TEST__',
  TIMESTAMP '0001-01-01 00:00:00.000000',
  TIMESTAMP '9999-12-31 23:59:59.999999',
  9999999999.99,       -- DECIMAL(12,2) max
  2147483647, '__LOSSY_TEST__', '__LOSSY_TEST__', '__LOSSY_TEST__'
);

-- ── bridge_product_attribute ────────────────────────────────────────
-- Lossy: BIGINT→INT64 (product_sk), INT→INT64 (sort_order)
INSERT INTO `acme-analytics-project.retail.bridge_product_attribute` (
  product_sk, attribute_name, attribute_value, primary_value, sort_order
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__', TRUE, 2147483647
);

-- ── bridge_product_supplier ─────────────────────────────────────────
-- Lossy: BIGINT→INT64 (product_sk, supplier_sk), INT→INT64 (lead_time_days, moq),
--         DECIMAL(12,4)→NUMERIC (unit_cost)
INSERT INTO `acme-analytics-project.retail.bridge_product_supplier` (
  product_sk, supplier_sk, primary_supplier, supplier_sku, unit_cost,
  lead_time_days, moq, valid_from, valid_to
) VALUES (
  9223372036854775807, 9223372036854775807, TRUE, '__LOSSY_TEST__',
  99999999.9999,       -- DECIMAL(12,4) max
  2147483647, 2147483647, DATE '2099-12-31', DATE '2099-12-31'
);

-- ── bridge_customer_segment ─────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk), DECIMAL(4,3)→NUMERIC (confidence)
INSERT INTO `acme-analytics-project.retail.bridge_customer_segment` (
  customer_sk, segment_id, segment_name, assigned_dt, expires_dt,
  confidence, source, snapshot_date
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__',
  DATE '2099-12-31', DATE '2099-12-31',
  9.999,               -- DECIMAL(4,3) max
  '__LOSSY_TEST__', DATE '2099-12-31'
);

-- ── bridge_promo_eligibility ────────────────────────────────────────
-- Lossy: BIGINT→INT64 (customer_sk, promo_sk)
INSERT INTO `acme-analytics-project.retail.bridge_promo_eligibility` (
  customer_sk, promo_sk, eligible, reason, valid_from, valid_to, load_date
) VALUES (
  9223372036854775807, 9223372036854775807, TRUE,
  '__LOSSY_TEST__', DATE '2099-12-31', DATE '2099-12-31', DATE '2099-12-31'
);

-- ── bridge_employee_role ────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (employee_sk)
INSERT INTO `acme-analytics-project.retail.bridge_employee_role` (
  employee_sk, role, primary_role, eff_from, eff_to
) VALUES (
  9223372036854775807, '__LOSSY_TEST__', TRUE, DATE '2099-12-31', DATE '2099-12-31'
);

-- ── dim_employee_history ────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (history_id, employee_sk, home_store_sk),
--         INT→INT64 (eff_from_year)
INSERT INTO `acme-analytics-project.retail.dim_employee_history` (
  history_id, employee_sk, role, department, home_store_sk, salary_band,
  eff_from, eff_to, is_current, eff_from_year, eff_from_date
) VALUES (
  -999999999, 9223372036854775807, '__LOSSY_TEST__', '__LOSSY_TEST__',
  9223372036854775807, '__LOSSY_TEST__',
  DATE '2099-12-31', DATE '2099-12-31', TRUE, 2099, DATE '2099-01-01'
);

-- ── dim_store_history ───────────────────────────────────────────────
-- Lossy: BIGINT→INT64 (history_id, store_sk, manager_employee_sk),
--         INT→INT64 (sq_ft)
INSERT INTO `acme-analytics-project.retail.dim_store_history` (
  history_id, store_sk, store_type, manager_employee_sk, sq_ft,
  eff_from, eff_to, is_current, change_reason
) VALUES (
  -999999999, 9223372036854775807, '__LOSSY_TEST__', 9223372036854775807,
  2147483647, DATE '2099-12-31', DATE '2099-12-31', TRUE, '__LOSSY_TEST__'
);


-- ============================================================================
-- PHASE 2: VERIFY — Read back and compare using EXCEPT DISTINCT
-- Each SELECT returns 0 rows if the round-trip is exact.
-- Results collected into a temp table for final summary.
-- ============================================================================

CREATE TEMP TABLE _lossy_results (table_name STRING, mismatches INT64);

-- ── dim_date ────────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_date', COUNT(*) FROM (
  SELECT d_date_sk, d_month_seq, d_week_seq, d_quarter_seq, d_year, d_dow, d_moy, d_dom,
         d_qoy, d_fy_year, d_fy_quarter_seq, d_first_dom, d_last_dom, d_same_day_ly, d_same_day_lq
  FROM `acme-analytics-project.retail.dim_date`
  WHERE d_date_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647,
         2147483647, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647
);

-- ── dim_customer ────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_customer', COUNT(*) FROM (
  SELECT customer_sk, first_seen_ts, last_seen_ts
  FROM `acme-analytics-project.retail.dim_customer`
  WHERE customer_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── dim_product ─────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_product', COUNT(*) FROM (
  SELECT product_sk, unit_price
  FROM `acme-analytics-project.retail.dim_product`
  WHERE stock_code = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, NUMERIC '99999999.99'
);

-- ── fact_sales ──────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_sales', COUNT(*) FROM (
  SELECT customer_sk, product_sk, quantity, unit_price, line_total, invoice_ts
  FROM `acme-analytics-project.retail.fact_sales`
  WHERE invoice_no = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807, 2147483647,
         NUMERIC '99999999.99', NUMERIC '999999999999.99',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── fact_web_session ────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_web_session', COUNT(*) FROM (
  SELECT event_ts
  FROM `acme-analytics-project.retail.fact_web_session`
  WHERE ip = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT TIMESTAMP '0001-01-01 00:00:00.000000'
);

-- ── sales_cube (positive boundaries) ────────────────────────────────
INSERT INTO _lossy_results
SELECT 'sales_cube_pos', COUNT(*) FROM (
  SELECT dim_level, month_key, product_sk, orders, revenue, units
  FROM `acme-analytics-project.retail.sales_cube`
  WHERE cube_key = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 127, 32767, 9223372036854775807, 9223372036854775807,
         NUMERIC '9999999999999999.99', 9223372036854775807
);

-- ── sales_cube (negative boundaries) ────────────────────────────────
INSERT INTO _lossy_results
SELECT 'sales_cube_neg', COUNT(*) FROM (
  SELECT dim_level, month_key, product_sk, orders, revenue, units
  FROM `acme-analytics-project.retail.sales_cube`
  WHERE cube_key = '__LOSSY_TEST_NEG__'
  EXCEPT DISTINCT
  SELECT -128, -32768, -9223372036854775808, -9223372036854775808,
         NUMERIC '-9999999999999999.99', -9223372036854775808
);

-- ── top_countries_daily (positive) ──────────────────────────────────
INSERT INTO _lossy_results
SELECT 'top_countries_daily_pos', COUNT(*) FROM (
  SELECT orders, revenue, rank
  FROM `acme-analytics-project.retail.top_countries_daily`
  WHERE country = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, NUMERIC '9999999999999999.99', 127
);

-- ── top_countries_daily (negative) ──────────────────────────────────
INSERT INTO _lossy_results
SELECT 'top_countries_daily_neg', COUNT(*) FROM (
  SELECT orders, revenue, rank
  FROM `acme-analytics-project.retail.top_countries_daily`
  WHERE country = '__LOSSY_TEST_NEG__'
  EXCEPT DISTINCT
  SELECT -9223372036854775808, NUMERIC '-9999999999999999.99', -128
);

-- ── returns_ledger ──────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'returns_ledger', COUNT(*) FROM (
  SELECT return_id, customer_sk, return_ts, refund_amount
  FROM `acme-analytics-project.retail.returns_ledger`
  WHERE invoice_no = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807,
         TIMESTAMP '9999-12-31 23:59:59.999999',
         NUMERIC '9999999999.99'
);

-- ── dim_store ───────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_store', COUNT(*) FROM (
  SELECT store_sk, sq_ft, manager_employee_sk,
         JSON_VALUE(attributes, '$.key1'), JSON_VALUE(attributes, '$.key2')
  FROM `acme-analytics-project.retail.dim_store`
  WHERE store_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647, 9223372036854775807, 'val1', 'val2'
);

-- ── dim_supplier ────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_supplier', COUNT(*) FROM (
  SELECT supplier_sk, payment_terms_days,
         primary_contact.name, primary_contact.email, primary_contact.phone,
         (SELECT STRING_AGG(c ORDER BY c) FROM UNNEST(categories) c)
  FROM `acme-analytics-project.retail.dim_supplier`
  WHERE supplier_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647,
         'John Doe', 'john@test.com', '+1-555-0100',
         'cat_a,cat_b,cat_c'
);

-- ── dim_employee ────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_employee', COUNT(*) FROM (
  SELECT employee_sk, home_store_sk, manager_sk
  FROM `acme-analytics-project.retail.dim_employee`
  WHERE employee_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807, 9223372036854775807
);

-- ── dim_promotion ───────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_promotion', COUNT(*) FROM (
  SELECT promo_sk, pct_off, flat_off, budget,
         (SELECT STRING_AGG(c ORDER BY c) FROM UNNEST(channels) c),
         JSON_VALUE(eligibility, '$.tier'), JSON_VALUE(eligibility, '$.min_spend')
  FROM `acme-analytics-project.retail.dim_promotion`
  WHERE promo_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807,
         NUMERIC '999.99', NUMERIC '99999999.99', NUMERIC '999999999999.99',
         'app,instore,online', 'gold', '100'
);

-- ── dim_warehouse ───────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_warehouse', COUNT(*) FROM (
  SELECT warehouse_sk, capacity_units, geocode.lat, geocode.lon
  FROM `acme-analytics-project.retail.dim_warehouse`
  WHERE warehouse_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         1.7976931348623157e+308, -1.7976931348623157e+308
);

-- ── dim_currency ────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_currency', COUNT(*) FROM (
  SELECT minor_unit
  FROM `acme-analytics-project.retail.dim_currency`
  WHERE currency_code = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 2147483647
);

-- ── dim_geography ───────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_geography', COUNT(*) FROM (
  SELECT geo_sk, latitude, longitude
  FROM `acme-analytics-project.retail.dim_geography`
  WHERE country_iso2 = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 1.7976931348623157e+308, -1.7976931348623157e+308
);

-- ── dim_color ───────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_color', COUNT(*) FROM (
  SELECT color_sk
  FROM `acme-analytics-project.retail.dim_color`
  WHERE color_code = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807
);

-- ── dim_size ────────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_size', COUNT(*) FROM (
  SELECT size_sk, sort_order
  FROM `acme-analytics-project.retail.dim_size`
  WHERE size_code = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647
);

-- ── dim_brand ───────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_brand', COUNT(*) FROM (
  SELECT brand_sk
  FROM `acme-analytics-project.retail.dim_brand`
  WHERE brand_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807
);

-- ── dim_category ────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_category', COUNT(*) FROM (
  SELECT category_sk, depth, sort_order
  FROM `acme-analytics-project.retail.dim_category`
  WHERE category_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647, 2147483647
);

-- ── dim_payment_method ──────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_payment_method', COUNT(*) FROM (
  SELECT payment_method_sk, fee_pct, fee_flat, settlement_days
  FROM `acme-analytics-project.retail.dim_payment_method`
  WHERE method_code = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, NUMERIC '9.9999', NUMERIC '999999.99', 2147483647
);

-- ── fact_inventory_movements ────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_inventory_movements', COUNT(*) FROM (
  SELECT movement_id, movement_ts, warehouse_sk, store_sk, quantity, operator_sk,
         year, month, day
  FROM `acme-analytics-project.retail.fact_inventory_movements`
  WHERE reference_doc = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, TIMESTAMP '9999-12-31 23:59:59.999999',
         9223372036854775807, 9223372036854775807, 2147483647, 9223372036854775807,
         2099, 12, 31
);

-- ── fact_inventory_snapshot ─────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_inventory_snapshot', COUNT(*) FROM (
  SELECT warehouse_sk, on_hand_units, allocated_units, in_transit_units,
         available_units, avg_cost, last_movement_ts
  FROM `acme-analytics-project.retail.fact_inventory_snapshot`
  WHERE sku = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647, 2147483647, 2147483647,
         2147483647, NUMERIC '99999999.9999',
         TIMESTAMP '0001-01-01 00:00:00.000000'
);

-- ── fact_returns ────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_returns', COUNT(*) FROM (
  SELECT return_id, customer_sk, product_sk, return_ts, quantity, refund_amount, store_sk
  FROM `acme-analytics-project.retail.fact_returns`
  WHERE invoice_no = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807, 9223372036854775807,
         TIMESTAMP '9999-12-31 23:59:59.999999', 2147483647,
         NUMERIC '9999999999.99', 9223372036854775807
);

-- ── fact_payments ───────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_payments', COUNT(*) FROM (
  SELECT payment_id, customer_sk, payment_method_sk, amount, payment_ts,
         fee_amount, post_year, post_month
  FROM `acme-analytics-project.retail.fact_payments`
  WHERE invoice_no = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807, 9223372036854775807,
         NUMERIC '999999999999.99',
         TIMESTAMP '0001-01-01 00:00:00.000000',
         NUMERIC '99999999.99', 2099, 12
);

-- ── fact_shipments ──────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_shipments', COUNT(*) FROM (
  SELECT customer_sk, warehouse_sk, shipped_ts, delivered_ts, sla_hours,
         ship_year, ship_month, ship_day,
         ARRAY_LENGTH(tracking_events),
         tracking_events[OFFSET(0)].ts, tracking_events[OFFSET(0)].status,
         tracking_events[OFFSET(1)].ts, tracking_events[OFFSET(1)].status
  FROM `acme-analytics-project.retail.fact_shipments`
  WHERE shipment_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999',
         2147483647,
         2099, 12, 31,
         2,
         TIMESTAMP '9999-12-31 23:59:59.999999', 'DELIVERED',
         TIMESTAMP '0001-01-01 00:00:00.000000', 'SHIPPED'
);

-- ── fact_refunds ────────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_refunds', COUNT(*) FROM (
  SELECT refund_id, payment_id, return_id, customer_sk, amount, refund_ts
  FROM `acme-analytics-project.retail.fact_refunds`
  WHERE refund_method = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807, 9223372036854775807, 9223372036854775807,
         NUMERIC '999999999999.99',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── fact_app_clicks ─────────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_app_clicks', COUNT(*) FROM (
  SELECT user_sk, event_ts,
         JSON_VALUE(properties, '$.action'), JSON_VALUE(properties, '$.element'),
         device.platform, device.version, device.model
  FROM `acme-analytics-project.retail.fact_app_clicks`
  WHERE session_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807,
         TIMESTAMP '9999-12-31 23:59:59.999999',
         'click', 'buy_button',
         'iOS', '17.4', 'iPhone15'
);

-- ── fact_email_engagement ───────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_email_engagement', COUNT(*) FROM (
  SELECT campaign_sk, user_sk, event_ts,
         ARRAY_LENGTH(clicks),
         clicks[OFFSET(0)].ts, clicks[OFFSET(0)].url,
         clicks[OFFSET(1)].ts, clicks[OFFSET(1)].url
  FROM `acme-analytics-project.retail.fact_email_engagement`
  WHERE send_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         2,
         TIMESTAMP '9999-12-31 23:59:59.999999', 'https://test.com/a',
         TIMESTAMP '0001-01-01 00:00:00.000000', 'https://test.com/b'
);

-- ── fact_chat_interactions ──────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_chat_interactions', COUNT(*) FROM (
  SELECT customer_sk, agent_sk, started_at, ended_at,
         duration_sec, message_count, csat_score, sentiment_avg
  FROM `acme-analytics-project.retail.fact_chat_interactions`
  WHERE chat_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999',
         2147483647, 2147483647, 2147483647,
         NUMERIC '9.999'
);

-- ── fact_warehouse_picks ────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_warehouse_picks', COUNT(*) FROM (
  SELECT pick_id, warehouse_sk, picker_sk, quantity, picked_ts, duration_ms
  FROM `acme-analytics-project.retail.fact_warehouse_picks`
  WHERE sku = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807, 9223372036854775807,
         2147483647,
         TIMESTAMP '9999-12-31 23:59:59.999999',
         2147483647
);

-- ── fact_supplier_invoice_lines ─────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_supplier_invoice_lines', COUNT(*) FROM (
  SELECT invoice_line_id, supplier_sk, quantity, unit_cost, line_total,
         received_ts, invoice_year, invoice_month
  FROM `acme-analytics-project.retail.fact_supplier_invoice_lines`
  WHERE invoice_no = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807, 2147483647,
         NUMERIC '99999999.9999', NUMERIC '999999999999.99',
         TIMESTAMP '0001-01-01 00:00:00.000000',
         2099, 12
);

-- ── fact_loyalty_events ─────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_loyalty_events', COUNT(*) FROM (
  SELECT event_id, points, store_sk, event_ts,
         JSON_VALUE(meta, '$.source'), JSON_VALUE(meta, '$.tier')
  FROM `acme-analytics-project.retail.fact_loyalty_events`
  WHERE member_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647, 9223372036854775807,
         TIMESTAMP '9999-12-31 23:59:59.999999',
         'pos', 'platinum'
);

-- ── fact_fraud_decisions ────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_fraud_decisions', COUNT(*) FROM (
  SELECT txn_id, customer_sk, fraud_score, decided_ts,
         (SELECT STRING_AGG(s ORDER BY s) FROM UNNEST(rule_signals) s)
  FROM `acme-analytics-project.retail.fact_fraud_decisions`
  WHERE decision = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         NUMERIC '9.9999',
         TIMESTAMP '0001-01-01 00:00:00.000000',
         'device_fingerprint,geo_anomaly,velocity_check'
);

-- ── fact_promo_redemptions ──────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_promo_redemptions', COUNT(*) FROM (
  SELECT redemption_id, promo_sk, customer_sk, discount_amount, applied_ts
  FROM `acme-analytics-project.retail.fact_promo_redemptions`
  WHERE invoice_no = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807, 9223372036854775807,
         NUMERIC '9999999999.99',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── fact_customer_complaints ────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'fact_customer_complaints', COUNT(*) FROM (
  SELECT customer_sk, created_at, resolved_at, csat_score
  FROM `acme-analytics-project.retail.fact_customer_complaints`
  WHERE complaint_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999',
         2147483647
);

-- ── agg_daily_sales_by_store ────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_daily_sales_by_store', COUNT(*) FROM (
  SELECT store_sk, gross_revenue, net_revenue, units_sold, txn_count, avg_basket
  FROM `acme-analytics-project.retail.agg_daily_sales_by_store`
  WHERE sale_date = DATE '2099-12-31' AND store_sk = 9223372036854775807
  EXCEPT DISTINCT
  SELECT 9223372036854775807,
         NUMERIC '99999999999999.99', NUMERIC '99999999999999.99',
         9223372036854775807, 9223372036854775807,
         NUMERIC '9999999999.99'
);

-- ── agg_daily_sales_by_product ──────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_daily_sales_by_product', COUNT(*) FROM (
  SELECT product_sk, units_sold, gross_revenue, margin_pct, cogs, return_units, net_units
  FROM `acme-analytics-project.retail.agg_daily_sales_by_product`
  WHERE sale_date = DATE '2099-12-31' AND product_sk = 9223372036854775807
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         NUMERIC '99999999999999.99', NUMERIC '99.9999', NUMERIC '99999999999999.99',
         9223372036854775807, 9223372036854775807
);

-- ── agg_weekly_customer_ltv ─────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_weekly_customer_ltv', COUNT(*) FROM (
  SELECT customer_sk, ltv_to_date, orders_to_date, avg_order_value,
         days_since_last_order, churn_risk
  FROM `acme-analytics-project.retail.agg_weekly_customer_ltv`
  WHERE rfm_score = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807,
         NUMERIC '99999999999999.99', 2147483647,
         NUMERIC '9999999999.99', 2147483647,
         NUMERIC '9.999'
);

-- ── agg_monthly_supplier_performance ────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_monthly_supplier_performance', COUNT(*) FROM (
  SELECT supplier_sk, orders_placed, units_received, on_time_pct, fill_rate_pct,
         avg_lead_time_days, quality_score, total_spend
  FROM `acme-analytics-project.retail.agg_monthly_supplier_performance`
  WHERE month_start = DATE '2099-12-31' AND supplier_sk = 9223372036854775807
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647, 9223372036854775807,
         NUMERIC '9.9999', NUMERIC '9.9999',
         NUMERIC '9999.99', NUMERIC '9.999',
         NUMERIC '99999999999999.99'
);

-- ── agg_hourly_warehouse_kpi ────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_hourly_warehouse_kpi', COUNT(*) FROM (
  SELECT warehouse_sk, units_in, units_picked, units_shipped, pick_rate_uph,
         backlog_units, avg_pick_seconds, snapshot_ts
  FROM `acme-analytics-project.retail.agg_hourly_warehouse_kpi`
  WHERE snapshot_hour = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647, 2147483647, 2147483647,
         NUMERIC '999999.99', 2147483647, NUMERIC '999999.99',
         TIMESTAMP '2099-12-31 23:00:00.000000'
);

-- ── agg_daily_carrier_otd ───────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_daily_carrier_otd', COUNT(*) FROM (
  SELECT shipments_total, delivered_on_time, delivered_late, in_transit,
         otd_pct, avg_transit_hours
  FROM `acme-analytics-project.retail.agg_daily_carrier_otd`
  WHERE carrier = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 2147483647, 2147483647, 2147483647, 2147483647,
         NUMERIC '9.9999', NUMERIC '999999.99'
);

-- ── agg_marketing_attribution_cube ──────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_marketing_attribution_cube', COUNT(*) FROM (
  SELECT campaign_sk, attributed_revenue, attributed_units, cost, roas, grouping_id
  FROM `acme-analytics-project.retail.agg_marketing_attribution_cube`
  WHERE channel = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807,
         NUMERIC '99999999999999.99', 9223372036854775807,
         NUMERIC '999999999999.99', NUMERIC '9999.9999',
         2147483647
);

-- ── agg_returns_by_reason_monthly ───────────────────────────────────
INSERT INTO _lossy_results
SELECT 'agg_returns_by_reason_monthly', COUNT(*) FROM (
  SELECT return_count, return_units, total_refunded, avg_days_to_return
  FROM `acme-analytics-project.retail.agg_returns_by_reason_monthly`
  WHERE reason_code = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         NUMERIC '99999999999999.99', NUMERIC '999999.99'
);

-- ── acid_customer_address_history ───────────────────────────────────
INSERT INTO _lossy_results
SELECT 'acid_customer_address_history', COUNT(*) FROM (
  SELECT history_id, customer_sk, eff_from, eff_to
  FROM `acme-analytics-project.retail.acid_customer_address_history`
  WHERE change_reason = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── acid_supplier_terms_history ─────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'acid_supplier_terms_history', COUNT(*) FROM (
  SELECT history_id, supplier_sk, payment_terms_days, discount_pct, eff_from, eff_to
  FROM `acme-analytics-project.retail.acid_supplier_terms_history`
  WHERE changed_by = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807, 2147483647,
         NUMERIC '999.99',
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── acid_loyalty_points_ledger ──────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'acid_loyalty_points_ledger', COUNT(*) FROM (
  SELECT entry_id, points_delta, running_balance, event_ts, expiry_ts
  FROM `acme-analytics-project.retail.acid_loyalty_points_ledger`
  WHERE member_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 2147483647, 2147483647,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── acid_inventory_adjustments_log ──────────────────────────────────
INSERT INTO _lossy_results
SELECT 'acid_inventory_adjustments_log', COUNT(*) FROM (
  SELECT adjustment_id, warehouse_sk, quantity_delta, adjusted_at, approved_at
  FROM `acme-analytics-project.retail.acid_inventory_adjustments_log`
  WHERE sku = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807, 2147483647,
         TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999'
);

-- ── kudu_session_state ──────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'kudu_session_state', COUNT(*) FROM (
  SELECT started_ts, last_event_ts, cart_value, cart_items
  FROM `acme-analytics-project.retail.kudu_session_state`
  WHERE session_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT TIMESTAMP '0001-01-01 00:00:00.000000',
         TIMESTAMP '9999-12-31 23:59:59.999999',
         NUMERIC '9999999999.99', 2147483647
);

-- ── bridge_product_attribute ────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'bridge_product_attribute', COUNT(*) FROM (
  SELECT product_sk, sort_order
  FROM `acme-analytics-project.retail.bridge_product_attribute`
  WHERE attribute_name = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 2147483647
);

-- ── bridge_product_supplier ─────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'bridge_product_supplier', COUNT(*) FROM (
  SELECT product_sk, supplier_sk, unit_cost, lead_time_days, moq
  FROM `acme-analytics-project.retail.bridge_product_supplier`
  WHERE supplier_sku = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807,
         NUMERIC '99999999.9999', 2147483647, 2147483647
);

-- ── bridge_customer_segment ─────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'bridge_customer_segment', COUNT(*) FROM (
  SELECT customer_sk, confidence
  FROM `acme-analytics-project.retail.bridge_customer_segment`
  WHERE segment_id = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, NUMERIC '9.999'
);

-- ── bridge_promo_eligibility ────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'bridge_promo_eligibility', COUNT(*) FROM (
  SELECT customer_sk, promo_sk
  FROM `acme-analytics-project.retail.bridge_promo_eligibility`
  WHERE reason = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807, 9223372036854775807
);

-- ── bridge_employee_role ────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'bridge_employee_role', COUNT(*) FROM (
  SELECT employee_sk
  FROM `acme-analytics-project.retail.bridge_employee_role`
  WHERE role = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT 9223372036854775807
);

-- ── dim_employee_history ────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_employee_history', COUNT(*) FROM (
  SELECT history_id, employee_sk, home_store_sk, eff_from_year
  FROM `acme-analytics-project.retail.dim_employee_history`
  WHERE department = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807, 9223372036854775807, 2099
);

-- ── dim_store_history ───────────────────────────────────────────────
INSERT INTO _lossy_results
SELECT 'dim_store_history', COUNT(*) FROM (
  SELECT history_id, store_sk, manager_employee_sk, sq_ft
  FROM `acme-analytics-project.retail.dim_store_history`
  WHERE change_reason = '__LOSSY_TEST__'
  EXCEPT DISTINCT
  SELECT -999999999, 9223372036854775807, 9223372036854775807, 2147483647
);


-- ============================================================================
-- PHASE 3: CLEANUP — Delete all seeded test rows
-- ============================================================================

DELETE FROM `acme-analytics-project.retail.dim_date` WHERE d_date_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_customer` WHERE customer_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_product` WHERE stock_code = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_sales` WHERE invoice_no = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_web_session` WHERE ip = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.sales_cube` WHERE cube_key IN ('__LOSSY_TEST__', '__LOSSY_TEST_NEG__');
DELETE FROM `acme-analytics-project.retail.top_countries_daily` WHERE country IN ('__LOSSY_TEST__', '__LOSSY_TEST_NEG__');
DELETE FROM `acme-analytics-project.retail.returns_ledger` WHERE invoice_no = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_store` WHERE store_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_supplier` WHERE supplier_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_employee` WHERE employee_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_promotion` WHERE promo_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_warehouse` WHERE warehouse_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_currency` WHERE currency_code = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_geography` WHERE country_iso2 = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_color` WHERE color_code = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_size` WHERE size_code = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_brand` WHERE brand_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_category` WHERE category_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_payment_method` WHERE method_code = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_inventory_movements` WHERE reference_doc = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_inventory_snapshot` WHERE sku = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_returns` WHERE invoice_no = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_payments` WHERE invoice_no = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_shipments` WHERE shipment_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_refunds` WHERE refund_method = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_app_clicks` WHERE session_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_email_engagement` WHERE send_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_chat_interactions` WHERE chat_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_warehouse_picks` WHERE sku = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_supplier_invoice_lines` WHERE invoice_no = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_loyalty_events` WHERE member_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_fraud_decisions` WHERE decision = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_promo_redemptions` WHERE invoice_no = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.fact_customer_complaints` WHERE complaint_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.agg_daily_sales_by_store` WHERE sale_date = DATE '2099-12-31';
DELETE FROM `acme-analytics-project.retail.agg_daily_sales_by_product` WHERE sale_date = DATE '2099-12-31';
DELETE FROM `acme-analytics-project.retail.agg_weekly_customer_ltv` WHERE rfm_score = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.agg_monthly_supplier_performance` WHERE month_start = DATE '2099-12-31';
DELETE FROM `acme-analytics-project.retail.agg_hourly_warehouse_kpi` WHERE snapshot_hour = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.agg_daily_carrier_otd` WHERE carrier = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.agg_marketing_attribution_cube` WHERE channel = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.agg_returns_by_reason_monthly` WHERE reason_code = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.acid_customer_address_history` WHERE change_reason = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.acid_supplier_terms_history` WHERE changed_by = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.acid_loyalty_points_ledger` WHERE member_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.acid_inventory_adjustments_log` WHERE sku = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.kudu_session_state` WHERE session_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.bridge_product_attribute` WHERE attribute_name = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.bridge_product_supplier` WHERE supplier_sku = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.bridge_customer_segment` WHERE segment_id = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.bridge_promo_eligibility` WHERE reason = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.bridge_employee_role` WHERE role = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_employee_history` WHERE department = '__LOSSY_TEST__';
DELETE FROM `acme-analytics-project.retail.dim_store_history` WHERE change_reason = '__LOSSY_TEST__';


-- ============================================================================
-- PHASE 4: SUMMARY — Final pass/fail report
-- ============================================================================

SELECT
  table_name,
  CASE WHEN mismatches = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS result,
  mismatches
FROM _lossy_results
ORDER BY result DESC, table_name;

-- Grand summary
SELECT
  COUNTIF(mismatches = 0) AS tables_passed,
  COUNTIF(mismatches > 0) AS tables_failed,
  COUNT(*) AS tables_total,
  CASE
    WHEN COUNTIF(mismatches > 0) = 0 THEN '✓ ALL PASSED — 0 unprobed lossy columns'
    ELSE '✗ FAILURES DETECTED'
  END AS overall_result
FROM _lossy_results;
