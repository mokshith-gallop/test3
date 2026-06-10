#!/bin/bash
# AC #2: Column parity & type correctness validation
# Extracts columns from source HQL and target SQL, compares each table.

set -euo pipefail

SRC_DIR="/workspace/source/clusters/acme-analytics/hive"
TGT_DIR="/workspace/project/retail/ddl"

TOTAL_TABLES=0
TOTAL_PASS=0
TOTAL_FAIL=0
FAILURES=""

# Function: extract column names from a Hive CREATE TABLE block
extract_hive_columns() {
  local file="$1"
  local table="$2"
  # Grab columns between CREATE TABLE and closing ), plus PARTITIONED BY columns
  awk -v tbl="retail.$table" '
    $0 ~ "CREATE TABLE " tbl " " { in_block=1; next }
    $0 ~ "CREATE TABLE " tbl "$" { in_block=1; next }
    in_block && /^\)/ { in_block=0 }
    in_block && /PARTITIONED BY/ { in_part=1; next }
    in_part && /^\)/ { in_part=0 }
    in_block && /^\s+[a-z_]/ { gsub(/^[ \t]+/, ""); split($0, a, /[ \t]+/); print a[1] }
    in_part && /^\s+[a-z_]/ { gsub(/^[ \t]+/, ""); split($0, a, /[ \t]+/); print a[1] }
  ' "$file" | sed 's/,$//' | sort
}

# Function: extract column names from a BQ CREATE OR REPLACE TABLE block
extract_bq_columns() {
  local file="$1"
  local table="$2"
  awk -v tbl="retail.$table" '
    $0 ~ "retail\\." tbl "`" { in_block=1; next }
    in_block && /^\)/ { in_block=0 }
    in_block && /^\s+[a-z_]/ { gsub(/^[ \t]+/, ""); split($0, a, /[ \t]+/); print a[1] }
  ' "$file" | sed 's/,$//' | sort
}

# Map: table -> source_file
declare -A TABLE_SRC
for t in dim_date dim_customer dim_product fact_sales fact_web_session; do
  TABLE_SRC[$t]="03-retail-tables.hql"
done
TABLE_SRC[returns_ledger]="06-acid-tables.hql"
TABLE_SRC[sales_cube]="08-rollup-etl.hql"
TABLE_SRC[top_countries_daily]="08-rollup-etl.hql"
for t in dim_store dim_supplier dim_employee dim_promotion dim_warehouse dim_currency dim_geography dim_color dim_size dim_brand dim_category dim_payment_method; do
  TABLE_SRC[$t]="10-additional-dims.hql"
done
for t in fact_inventory_movements fact_inventory_snapshot fact_returns fact_payments fact_shipments fact_refunds fact_app_clicks fact_email_engagement fact_chat_interactions fact_warehouse_picks fact_supplier_invoice_lines fact_loyalty_events fact_fraud_decisions fact_promo_redemptions fact_customer_complaints; do
  TABLE_SRC[$t]="11-additional-facts.hql"
done
for t in agg_daily_sales_by_store agg_daily_sales_by_product agg_weekly_customer_ltv agg_monthly_supplier_performance agg_hourly_warehouse_kpi agg_daily_carrier_otd agg_marketing_attribution_cube agg_returns_by_reason_monthly; do
  TABLE_SRC[$t]="12-aggregates-rollups.hql"
done
for t in acid_customer_address_history acid_supplier_terms_history acid_loyalty_points_ledger acid_inventory_adjustments_log; do
  TABLE_SRC[$t]="13-additional-acid-tables.hql"
done
TABLE_SRC[kudu_session_state]="14-kudu-realtime.hql"
for t in bridge_product_attribute bridge_product_supplier bridge_customer_segment bridge_promo_eligibility bridge_employee_role dim_employee_history dim_store_history; do
  TABLE_SRC[$t]="15-bridge-and-scd2.hql"
done

# Map: table -> target_file
declare -A TABLE_TGT
for t in dim_date dim_customer dim_product fact_sales fact_web_session sales_cube top_countries_daily; do
  TABLE_TGT[$t]="03-retail-tables.sql"
done
TABLE_TGT[returns_ledger]="06-acid-tables.sql"
for t in dim_store dim_supplier dim_employee dim_promotion dim_warehouse dim_currency dim_geography dim_color dim_size dim_brand dim_category dim_payment_method; do
  TABLE_TGT[$t]="10-additional-dims.sql"
done
for t in fact_inventory_movements fact_inventory_snapshot fact_returns fact_payments fact_shipments fact_refunds fact_app_clicks fact_email_engagement fact_chat_interactions fact_warehouse_picks fact_supplier_invoice_lines fact_loyalty_events fact_fraud_decisions fact_promo_redemptions fact_customer_complaints; do
  TABLE_TGT[$t]="11-additional-facts.sql"
done
for t in agg_daily_sales_by_store agg_daily_sales_by_product agg_weekly_customer_ltv agg_monthly_supplier_performance agg_hourly_warehouse_kpi agg_daily_carrier_otd agg_marketing_attribution_cube agg_returns_by_reason_monthly; do
  TABLE_TGT[$t]="12-aggregates-rollups.sql"
done
for t in acid_customer_address_history acid_supplier_terms_history acid_loyalty_points_ledger acid_inventory_adjustments_log; do
  TABLE_TGT[$t]="13-additional-acid-tables.sql"
done
TABLE_TGT[kudu_session_state]="14-kudu-realtime.sql"
for t in bridge_product_attribute bridge_product_supplier bridge_customer_segment bridge_promo_eligibility bridge_employee_role dim_employee_history dim_store_history; do
  TABLE_TGT[$t]="15-bridge-and-scd2.sql"
done

# Synthetic columns that are expected ADDITIONS (not in source)
declare -A SYNTHETIC_COLS
SYNTHETIC_COLS[fact_inventory_movements]="movement_date"
SYNTHETIC_COLS[fact_payments]="post_date"
SYNTHETIC_COLS[fact_shipments]="ship_date"
SYNTHETIC_COLS[fact_supplier_invoice_lines]="invoice_date"
SYNTHETIC_COLS[dim_employee_history]="eff_from_date"
SYNTHETIC_COLS[agg_hourly_warehouse_kpi]="snapshot_ts"

echo "====== AC #2: COLUMN PARITY VERIFICATION ======"
echo ""

for table in $(echo "${!TABLE_SRC[@]}" | tr ' ' '\n' | sort); do
  src_file="${TABLE_SRC[$table]}"
  tgt_file="${TABLE_TGT[$table]}"
  TOTAL_TABLES=$((TOTAL_TABLES + 1))
  
  # Extract source columns
  extract_hive_columns "$SRC_DIR/$src_file" "$table" > /tmp/src_cols.txt
  
  # Extract target columns
  extract_bq_columns "$TGT_DIR/$tgt_file" "$table" > /tmp/tgt_cols.txt
  
  # Get synthetic columns for this table (if any)
  synth="${SYNTHETIC_COLS[$table]:-}"
  
  # Check: every source column must be in target
  missing=""
  while IFS= read -r col; do
    if ! grep -q "^${col}$" /tmp/tgt_cols.txt; then
      missing="$missing $col"
    fi
  done < /tmp/src_cols.txt
  
  # Check: synthetic columns must be present
  synth_missing=""
  if [ -n "$synth" ]; then
    for s in $synth; do
      if ! grep -q "^${s}$" /tmp/tgt_cols.txt; then
        synth_missing="$synth_missing $s"
      fi
    done
  fi
  
  if [ -z "$missing" ] && [ -z "$synth_missing" ]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILURES="$FAILURES\n  ✗ $table: missing=[$missing] synth_missing=[$synth_missing]"
    echo "✗ $table: MISSING source cols=[$missing] synth=[$synth_missing]"
  fi
done

echo ""
echo "=== AC #2 COLUMN PARITY SUMMARY ==="
echo "Tables checked: $TOTAL_TABLES"
echo "Passed: $TOTAL_PASS"
echo "Failed: $TOTAL_FAIL"
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "✓ PASS — every source column present in target, all synthetic columns present"
else
  echo "✗ FAIL — $TOTAL_FAIL tables have column mismatches:"
  echo -e "$FAILURES"
fi
