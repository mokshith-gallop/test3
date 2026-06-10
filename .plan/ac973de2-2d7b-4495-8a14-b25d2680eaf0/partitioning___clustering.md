# Partitioning & Clustering

### Partitioning & Clustering Strategy for All 54 Tables

Per the locked project-level partitioning decision, all multi-column Hive partitions collapse to a single DATE/TIMESTAMP partition column, and all Hive bucketing keys become BigQuery `CLUSTER BY` columns. Secondary Hive partition dimensions move to `CLUSTER BY`.

#### Tables with Partitioning + Clustering

| Table | BQ Partition Column | BQ CLUSTER BY | Source Pattern | AC |
|---|---|---|---|---|
| `fact_sales` | `PARTITION BY sale_date` | `CLUSTER BY customer_sk` | `PARTITIONED BY (sale_date DATE) CLUSTERED BY (customer_sk) INTO 8 BUCKETS` | AC #3 ✓ |
| `fact_inventory_movements` | `PARTITION BY movement_date` | `CLUSTER BY region, sku` | `PARTITIONED BY (year, month, day, region) CLUSTERED BY (sku) INTO 32 BUCKETS` | AC #4 ✓ |
| `fact_payments` | `PARTITION BY post_date` | `CLUSTER BY payment_method_partition, invoice_no` | `PARTITIONED BY (post_year, post_month, payment_method_partition) CLUSTERED BY (invoice_no) INTO 16 BUCKETS` | AC #5 ✓ |
| `fact_shipments` | `PARTITION BY ship_date` | `CLUSTER BY carrier_partition, warehouse_sk` | `PARTITIONED BY (ship_year, ship_month, ship_day, carrier_partition) CLUSTERED BY (warehouse_sk) INTO 16 BUCKETS` | AC #6 ✓ |
| `fact_inventory_snapshot` | `PARTITION BY snapshot_date` | `CLUSTER BY sku` | `PARTITIONED BY (snapshot_date) CLUSTERED BY (sku) INTO 16 BUCKETS` | — |
| `fact_warehouse_picks` | `PARTITION BY pick_date` | `CLUSTER BY warehouse_partition, picker_sk` | `PARTITIONED BY (pick_date, warehouse_partition) CLUSTERED BY (picker_sk) INTO 8 BUCKETS` | — |
| `fact_supplier_invoice_lines` | `PARTITION BY invoice_date` | — | `PARTITIONED BY (invoice_year, invoice_month)` — synthetic DATE | — |
| `fact_web_session` | `PARTITION BY event_date` | `CLUSTER BY country` | `PARTITIONED BY (event_date, country)` — country moves to CLUSTER BY | — |
| `fact_app_clicks` | `PARTITION BY event_date` | `CLUSTER BY platform_partition` | `PARTITIONED BY (event_date, platform_partition)` | — |
| `dim_employee_history` | `PARTITION BY eff_from_date` | — | `PARTITIONED BY (eff_from_year INT)` — synthetic DATE | — |
| `agg_hourly_warehouse_kpi` | `PARTITION BY DATE(snapshot_ts)` | — | `PARTITIONED BY (snapshot_hour STRING)` — synthetic TIMESTAMP, partitioned by extracted DATE | — |

#### Tables with Partition Only (no clustering)

| Table | BQ Partition Column | Source Pattern |
|---|---|---|
| `fact_returns` | `PARTITION BY return_date` | `PARTITIONED BY (return_date DATE)` |
| `fact_refunds` | `PARTITION BY refund_date` | `PARTITIONED BY (refund_date DATE)` |
| `fact_email_engagement` | `PARTITION BY event_date` | `PARTITIONED BY (event_date DATE)` |
| `fact_chat_interactions` | `PARTITION BY start_date` | `PARTITIONED BY (start_date DATE)` |
| `fact_loyalty_events` | `PARTITION BY event_date` | `PARTITIONED BY (event_date DATE)` |
| `fact_fraud_decisions` | `PARTITION BY decision_date` | `PARTITIONED BY (decision_date DATE)` |
| `fact_promo_redemptions` | `PARTITION BY redemption_date` | `PARTITIONED BY (redemption_date DATE)` |
| `fact_customer_complaints` | `PARTITION BY created_date` | `PARTITIONED BY (created_date DATE)` |
| `agg_daily_sales_by_store` | `PARTITION BY sale_date` | `PARTITIONED BY (sale_date DATE)` |
| `agg_daily_sales_by_product` | `PARTITION BY sale_date` | `PARTITIONED BY (sale_date DATE)` |
| `agg_weekly_customer_ltv` | `PARTITION BY week_start_date` | `PARTITIONED BY (week_start_date DATE)` |
| `agg_monthly_supplier_performance` | `PARTITION BY month_start` | `PARTITIONED BY (month_start DATE)` |
| `agg_daily_carrier_otd` | `PARTITION BY ship_date` | `PARTITIONED BY (ship_date DATE)` |
| `agg_marketing_attribution_cube` | `PARTITION BY period_date` | `PARTITIONED BY (period_date DATE)` |
| `agg_returns_by_reason_monthly` | `PARTITION BY month_start` | `PARTITIONED BY (month_start DATE)` |
| `sales_cube` | `PARTITION BY as_of_date` | `PARTITIONED BY (as_of_date DATE)` |
| `bridge_customer_segment` | `PARTITION BY snapshot_date` | `PARTITIONED BY (snapshot_date DATE)` |
| `bridge_promo_eligibility` | `PARTITION BY load_date` | `PARTITIONED BY (load_date DATE)` |

#### Tables with Clustering Only (ACID tables — no partition in source, cluster from bucket key)

| Table | BQ CLUSTER BY | Source Pattern | AC |
|---|---|---|---|
| `returns_ledger` | `CLUSTER BY return_id` | `CLUSTERED BY (return_id) INTO 4 BUCKETS` | AC #7 ✓ |
| `acid_customer_address_history` | `CLUSTER BY customer_sk` | `CLUSTERED BY (customer_sk) INTO 8 BUCKETS` | — |
| `acid_supplier_terms_history` | `CLUSTER BY supplier_sk` | `CLUSTERED BY (supplier_sk) INTO 4 BUCKETS` | — |
| `acid_loyalty_points_ledger` | `CLUSTER BY member_id` | `CLUSTERED BY (member_id) INTO 8 BUCKETS` | — |
| `acid_inventory_adjustments_log` | `CLUSTER BY adjustment_id` | `CLUSTERED BY (adjustment_id) INTO 4 BUCKETS` | — |

#### Tables with No Partition or Clustering (small dimensions, bridges, reference tables)

All unpartitioned/unbucketed source tables remain unpartitioned in BigQuery:

`dim_date`, `dim_customer`, `dim_product`, `dim_store`, `dim_supplier`, `dim_employee`, `dim_promotion`, `dim_warehouse`, `dim_currency`, `dim_geography`, `dim_color`, `dim_size`, `dim_brand`, `dim_category`, `dim_payment_method`, `top_countries_daily`, `bridge_product_attribute`, `bridge_product_supplier`, `bridge_employee_role`, `dim_store_history`

#### Kudu Tables (per locked Kudu decision)

| Table | Target | Partition/Cluster | AC |
|---|---|---|---|
| `kudu_session_state` | BQ native | `CLUSTER BY session_id` | AC #8 ✓ |
| `kudu_inventory_realtime` | Bigtable + BQ external | Row key: `warehouse_id#sku` | AC #8 ✓ |
| `kudu_realtime_price` | Bigtable + BQ external | Row key: `sku#store_id` | AC #8 ✓ |
| `kudu_promo_eligibility` | Bigtable only | Row key: `customer_id#promo_id` | AC #8 ✓ |
