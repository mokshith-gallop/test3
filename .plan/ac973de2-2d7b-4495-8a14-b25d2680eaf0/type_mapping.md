# Type Mapping

### Complete Hive → BigQuery Type Mapping Table

#### Scalar Types

| Hive Type | BigQuery Type | Lossy? | Notes |
|---|---|---|---|
| `STRING` | `STRING` | No | Direct 1:1 |
| `BOOLEAN` | `BOOL` | No | Direct 1:1 |
| `INT` | `INT64` | No | Widening (32→64 bit) |
| `BIGINT` | `INT64` | No | Direct 1:1; boundary values tested in AC #9 |
| `TINYINT` | `INT64` | Yes | Widening (8→64 bit); affects `sales_cube.dim_level`, `top_countries_daily.rank` |
| `SMALLINT` | `INT64` | Yes | Widening (16→64 bit); affects `sales_cube.month_key` |
| `DATE` | `DATE` | No | Direct 1:1 |
| `TIMESTAMP` | `TIMESTAMP` | No | Both microsecond precision |
| `DOUBLE` | `FLOAT64` | No | IEEE 754 double; affects `dim_warehouse.geocode.lat/lon`, `dim_geography.latitude/longitude` |
| `DECIMAL(p,s)` (all) | `NUMERIC` | Yes | BQ NUMERIC = precision 38, scale 9. All source precisions fit. Round-trip tested per AC #9 |

#### DECIMAL Precision Inventory (all → NUMERIC)

| Precision | Columns Affected |
|---|---|
| `DECIMAL(10,2)` | dim_product.unit_price, kudu_realtime_price.price/list_price/cost |
| `DECIMAL(12,2)` | fact_returns.refund_amount, returns_ledger.refund_amount, kudu_session_state.cart_value, fact_promo_redemptions.discount_amount |
| `DECIMAL(14,2)` | fact_sales.line_total, fact_payments.amount/fee_amount, fact_refunds.amount, dim_promotion.budget, agg_marketing_attribution_cube.cost |
| `DECIMAL(16,2)` | agg_daily_sales_by_store.gross/net_revenue, agg_daily_sales_by_product.gross_revenue/cogs, agg_weekly_customer_ltv.ltv_to_date, agg_monthly_supplier_performance.total_spend, agg_returns_by_reason_monthly.total_refunded, sales_cube.revenue |
| `DECIMAL(18,2)` | top_countries_daily.revenue (AC #2 explicit) |
| `DECIMAL(12,4)` | fact_inventory_snapshot.avg_cost, bridge_product_supplier.unit_cost, fact_supplier_invoice_lines.unit_cost (AC #2 explicit) |
| `DECIMAL(5,4)` | kudu_realtime_price.margin_pct, dim_payment_method.fee_pct, agg_monthly_supplier_performance.on_time_pct/fill_rate_pct, agg_daily_carrier_otd.otd_pct, fact_fraud_decisions.fraud_score (AC #2 explicit) |
| `DECIMAL(5,2)` | dim_promotion.pct_off, acid_supplier_terms_history.discount_pct (AC #2 explicit) |
| `DECIMAL(4,3)` | fact_chat_interactions.sentiment_avg, agg_weekly_customer_ltv.churn_risk, bridge_customer_segment.confidence, agg_monthly_supplier_performance.quality_score |
| `DECIMAL(6,4)` | agg_daily_sales_by_product.margin_pct |
| `DECIMAL(6,2)` | agg_monthly_supplier_performance.avg_lead_time_days |
| `DECIMAL(8,2)` | dim_payment_method.fee_flat, agg_daily_sales_by_store.avg_basket, agg_weekly_customer_ltv.avg_order_value, agg_hourly_warehouse_kpi.pick_rate_uph/avg_pick_seconds, agg_daily_carrier_otd.avg_transit_hours, agg_returns_by_reason_monthly.avg_days_to_return |
| `DECIMAL(8,4)` | agg_marketing_attribution_cube.roas |

#### Complex Types

| Hive Type | BigQuery Type | Columns Affected |
|---|---|---|
| `MAP<STRING,STRING>` | `JSON` | dim_store.attributes, dim_promotion.eligibility, fact_app_clicks.properties, fact_loyalty_events.meta |
| `STRUCT<...>` | `STRUCT<...>` | dim_supplier.primary_contact → `STRUCT<name STRING, email STRING, phone STRING>`; dim_warehouse.geocode → `STRUCT<lat FLOAT64, lon FLOAT64>`; fact_app_clicks.device → `STRUCT<platform STRING, version STRING, model STRING>` |
| `ARRAY<STRING>` | `ARRAY<STRING>` | dim_supplier.categories, dim_promotion.channels, fact_fraud_decisions.rule_signals |
| `ARRAY<STRUCT<...>>` | `ARRAY<STRUCT<...>>` | fact_shipments.tracking_events → `ARRAY<STRUCT<ts TIMESTAMP, status STRING, location STRING>>`; fact_email_engagement.clicks → `ARRAY<STRUCT<ts TIMESTAMP, url STRING>>` |

#### Kudu-Specific Type Adjustments
- Kudu `BIGINT` timestamps (epoch millis: `last_updated_ts`, `started_ts`, `last_event_ts`, `valid_from_ts`, `valid_to_ts`, `updated_ts`) → `TIMESTAMP` in BigQuery native table (kudu_session_state) or remain as row key components in Bigtable
- Kudu `PRIMARY KEY` → informational only in BigQuery; Bigtable row key in Bigtable schemas

#### Synthetic Columns Added (not in source)
These new columns are added for partitioning. Original integer partition columns are **retained** as regular non-partition columns for backward compatibility:

| Table | New Column | Type | Derived From |
|---|---|---|---|
| fact_inventory_movements | `movement_date` | `DATE` | `year`, `month`, `day` |
| fact_payments | `post_date` | `DATE` | `post_year`, `post_month` (day defaults to 1) |
| fact_shipments | `ship_date` | `DATE` | `ship_year`, `ship_month`, `ship_day` |
| fact_supplier_invoice_lines | `invoice_date` | `DATE` | `invoice_year`, `invoice_month` (day defaults to 1) |
| dim_employee_history | `eff_from_date` | `DATE` | `eff_from_year` (month/day default to 1) |
| agg_hourly_warehouse_kpi | `snapshot_ts` | `TIMESTAMP` | Parsed from `snapshot_hour` STRING |

#### Original Partition/Bucket Columns Retained as Regular Columns
All original multi-column partition fields (`year`, `month`, `day`, `region`, `post_year`, `post_month`, `ship_year`, `ship_month`, `ship_day`, `carrier_partition`, `payment_method_partition`, `warehouse_partition`, `platform_partition`, `invoice_year`, `invoice_month`, `eff_from_year`, `snapshot_hour`, `country`) are retained in the BigQuery schema as regular (non-partition) columns with their mapped types (INT→INT64, STRING→STRING). This satisfies AC #2's "every source column is present" requirement.
