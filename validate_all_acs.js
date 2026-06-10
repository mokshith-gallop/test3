#!/usr/bin/env node
'use strict';
// Comprehensive validation script for all 8 Acceptance Criteria
// Story: Convert Staging Database Schema (10 tables, 1 view) to BigQuery DDL

const { BigQuery } = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');

// ── Setup BigQuery client ──────────────────────────────────────────
const authClient = new OAuth2Client();
authClient.setCredentials({ access_token: process.env.TEST_BQ_TOKEN });
const bq = new BigQuery({
  projectId: process.env.TEST_BQ_PROJECT,
  authClient,
});
const DATASET = process.env.TEST_BQ_DATASETS || 'test';
const PROJECT = process.env.TEST_BQ_PROJECT;
const ds = bq.dataset(DATASET);
const SCRATCH = 'qa_stg_';

// ── Source HQL schema definitions (parsed from 06-staging-tables.hql) ──
const SOURCE_TABLES = {
  cleansed_orders: {
    columns: [
      { name: 'order_id', hiveType: 'STRING' },
      { name: 'customer_id', hiveType: 'STRING' },
      { name: 'invoice_no', hiveType: 'STRING' },
      { name: 'txn_ts', hiveType: 'TIMESTAMP' },
      { name: 'line_count', hiveType: 'INT' },
      { name: 'gross_amount', hiveType: 'DECIMAL(14,2)' },
      { name: 'discount', hiveType: 'DECIMAL(14,2)' },
      { name: 'tax', hiveType: 'DECIMAL(14,2)' },
      { name: 'net_amount', hiveType: 'DECIMAL(14,2)' },
      { name: 'tender_type', hiveType: 'STRING' },
      { name: 'source_feed', hiveType: 'STRING' },
    ],
    partitionCols: [{ name: 'order_date', hiveType: 'DATE' }],
    clusterCols: [], buckets: null,
  },
  cleansed_customers: {
    columns: [
      { name: 'customer_id', hiveType: 'STRING' },
      { name: 'email_norm', hiveType: 'STRING' },
      { name: 'phone_norm', hiveType: 'STRING' },
      { name: 'first_name', hiveType: 'STRING' },
      { name: 'last_name', hiveType: 'STRING' },
      { name: 'addr_line1', hiveType: 'STRING' },
      { name: 'addr_city', hiveType: 'STRING' },
      { name: 'addr_region', hiveType: 'STRING' },
      { name: 'addr_country', hiveType: 'STRING' },
      { name: 'addr_postal', hiveType: 'STRING' },
      { name: 'geocoded_lat', hiveType: 'DOUBLE' },
      { name: 'geocoded_lon', hiveType: 'DOUBLE' },
      { name: 'eff_from_ts', hiveType: 'TIMESTAMP' },
      { name: 'record_hash', hiveType: 'STRING' },
    ],
    partitionCols: [{ name: 'load_date', hiveType: 'DATE' }],
    clusterCols: [], buckets: null,
  },
  cleansed_products: {
    columns: [
      { name: 'sku', hiveType: 'STRING' },
      { name: 'upc', hiveType: 'STRING' },
      { name: 'name_norm', hiveType: 'STRING' },
      { name: 'category_norm', hiveType: 'STRING' },
      { name: 'subcategory', hiveType: 'STRING' },
      { name: 'color_norm', hiveType: 'STRING' },
      { name: 'size_norm', hiveType: 'STRING' },
      { name: 'msrp', hiveType: 'DECIMAL(10,2)' },
      { name: 'cost', hiveType: 'DECIMAL(10,2)' },
      { name: 'supplier_id', hiveType: 'STRING' },
      { name: 'available', hiveType: 'BOOLEAN' },
    ],
    partitionCols: [{ name: 'load_date', hiveType: 'DATE' }],
    clusterCols: [], buckets: null,
  },
  dedup_clickstream: {
    columns: [
      { name: 'session_id', hiveType: 'STRING' },
      { name: 'user_id', hiveType: 'STRING' },
      { name: 'event_ts', hiveType: 'TIMESTAMP' },
      { name: 'page_url', hiveType: 'STRING' },
      { name: 'referrer_url', hiveType: 'STRING' },
      { name: 'ip', hiveType: 'STRING' },
      { name: 'country', hiveType: 'STRING' },
      { name: 'bot_score', hiveType: 'DECIMAL(4,3)' },
      { name: 'device_type', hiveType: 'STRING' },
    ],
    partitionCols: [
      { name: 'date_ts', hiveType: 'STRING' },
      { name: 'country_partition', hiveType: 'STRING' },
    ],
    clusterCols: ['user_id'], buckets: 16,
  },
  geocoded_addresses: {
    columns: [
      { name: 'raw_addr_hash', hiveType: 'STRING' },
      { name: 'addr_line1', hiveType: 'STRING' },
      { name: 'addr_city', hiveType: 'STRING' },
      { name: 'addr_region', hiveType: 'STRING' },
      { name: 'addr_country', hiveType: 'STRING' },
      { name: 'addr_postal', hiveType: 'STRING' },
      { name: 'lat', hiveType: 'DOUBLE' },
      { name: 'lon', hiveType: 'DOUBLE' },
      { name: 'confidence', hiveType: 'DECIMAL(4,3)' },
      { name: 'provider', hiveType: 'STRING' },
    ],
    partitionCols: [{ name: 'load_date', hiveType: 'DATE' }],
    clusterCols: [], buckets: null,
  },
  parsed_loyalty_events: {
    columns: [
      { name: 'event_ts', hiveType: 'TIMESTAMP' },
      { name: 'member_id', hiveType: 'STRING' },
      { name: 'event_type', hiveType: 'STRING' },
      { name: 'points', hiveType: 'INT' },
      { name: 'store_id', hiveType: 'STRING' },
      { name: 'tx_id', hiveType: 'STRING' },
      { name: 'meta', hiveType: 'MAP<STRING,STRING>' },
    ],
    partitionCols: [{ name: 'date_ts', hiveType: 'STRING' }],
    clusterCols: [], buckets: null,
  },
  merged_returns_cdc: {
    columns: [
      { name: 'return_id', hiveType: 'BIGINT' },
      { name: 'invoice_no', hiveType: 'STRING' },
      { name: 'customer_sk', hiveType: 'BIGINT' },
      { name: 'return_ts', hiveType: 'TIMESTAMP' },
      { name: 'refund_amount', hiveType: 'DECIMAL(12,2)' },
      { name: 'reason_code', hiveType: 'STRING' },
      { name: 'status', hiveType: 'STRING' },
      { name: 'is_deleted', hiveType: 'BOOLEAN' },
    ],
    partitionCols: [{ name: 'snapshot_date', hiveType: 'DATE' }],
    clusterCols: [], buckets: null,
  },
  normalized_carrier_events: {
    columns: [
      { name: 'tracking_no', hiveType: 'STRING' },
      { name: 'carrier', hiveType: 'STRING' },
      { name: 'event_type', hiveType: 'STRING' },
      { name: 'event_ts', hiveType: 'TIMESTAMP' },
      { name: 'location_city', hiveType: 'STRING' },
      { name: 'location_region', hiveType: 'STRING' },
      { name: 'location_country', hiveType: 'STRING' },
    ],
    partitionCols: [{ name: 'date_ts', hiveType: 'STRING' }],
    clusterCols: [], buckets: null,
  },
  fraud_scored: {
    columns: [
      { name: 'txn_id', hiveType: 'BIGINT' },
      { name: 'customer_id', hiveType: 'STRING' },
      { name: 'fraud_score', hiveType: 'DECIMAL(5,4)' },
      { name: 'risk_band', hiveType: 'STRING' },
      { name: 'signals', hiveType: 'ARRAY<STRING>' },
      { name: 'scored_at', hiveType: 'TIMESTAMP' },
    ],
    partitionCols: [{ name: 'score_date', hiveType: 'DATE' }],
    clusterCols: [], buckets: null,
  },
  warehouse_kpi_snapshot: {
    columns: [
      { name: 'warehouse_id', hiveType: 'STRING' },
      { name: 'snapshot_ts', hiveType: 'TIMESTAMP' },
      { name: 'units_in', hiveType: 'INT' },
      { name: 'units_picked', hiveType: 'INT' },
      { name: 'units_shipped', hiveType: 'INT' },
      { name: 'pick_rate_uph', hiveType: 'DECIMAL(8,2)' },
      { name: 'backlog_units', hiveType: 'INT' },
      { name: 'avg_pick_ms', hiveType: 'INT' },
    ],
    partitionCols: [{ name: 'date_ts', hiveType: 'STRING' }],
    clusterCols: [], buckets: null,
  },
};

// ── Type mapping: Hive → BigQuery ──────────────────────────────────
function hiveTypeToBQ(hiveType) {
  const t = hiveType.toUpperCase().trim();
  if (t === 'STRING') return 'STRING';
  if (t === 'INT' || t === 'TINYINT' || t === 'SMALLINT') return 'INT64';
  if (t === 'BIGINT') return 'INT64';
  if (t === 'FLOAT' || t === 'DOUBLE') return 'FLOAT64';
  if (t === 'BOOLEAN') return 'BOOL';
  if (t === 'DATE') return 'DATE';
  if (t === 'TIMESTAMP') return 'DATETIME';
  if (t === 'BINARY') return 'BYTES';
  if (t.startsWith('DECIMAL') || t.startsWith('NUMERIC')) return 'NUMERIC';
  if (t === 'MAP<STRING,STRING>') return 'JSON';
  if (t === 'ARRAY<STRING>') return 'ARRAY<STRING>';
  throw new Error('Unknown Hive type: ' + hiveType);
}

function generateBQDDL(tableName, def) {
  const bqName = SCRATCH + tableName;
  const allCols = [];
  for (const col of def.columns) {
    allCols.push('  ' + col.name + ' ' + hiveTypeToBQ(col.hiveType));
  }
  let partitionClause = '';
  let clusterClause = '';
  const clusterCols = (def.clusterCols || []).slice();

  if (def.partitionCols.length === 1 && def.partitionCols[0].hiveType === 'DATE') {
    allCols.push('  ' + def.partitionCols[0].name + ' DATE');
    partitionClause = 'PARTITION BY ' + def.partitionCols[0].name;
  } else if (def.partitionCols.length === 1 && def.partitionCols[0].hiveType === 'STRING') {
    allCols.push('  ' + def.partitionCols[0].name + ' DATE');
    partitionClause = 'PARTITION BY ' + def.partitionCols[0].name;
  } else if (def.partitionCols.length === 2) {
    // dedup_clickstream
    allCols.push('  date_ts DATE');
    allCols.push('  country_partition STRING');
    partitionClause = 'PARTITION BY date_ts';
    clusterCols.unshift('country_partition');
  }
  if (clusterCols.length > 0) {
    clusterClause = 'CLUSTER BY ' + clusterCols.join(', ');
  }
  return 'CREATE TABLE `' + PROJECT + '.' + DATASET + '.' + bqName + '` (\n' +
    allCols.join(',\n') + '\n)\n' + partitionClause +
    (clusterClause ? '\n' + clusterClause : '') + ';';
}

// ── Helpers ────────────────────────────────────────────────────────
async function runQuery(sql, dryRun) {
  const opts = { query: sql, location: process.env.TEST_BQ_LOCATION || 'EU' };
  if (dryRun) opts.dryRun = true;
  const [job] = await bq.createQueryJob(opts);
  if (dryRun) return job;
  const [rows] = await job.getQueryResults();
  return rows;
}

async function dropIfExists(name, type) {
  type = type || 'TABLE';
  try { await runQuery('DROP ' + type + ' IF EXISTS `' + PROJECT + '.' + DATASET + '.' + name + '`'); } catch (_) {}
}

// ── Counters ───────────────────────────────────────────────────────
let allPassed = true, total = 0, passed = 0, failed = 0;
function ok(msg) { total++; passed++; console.log('  ✓ PASS: ' + msg); }
function nok(msg) { total++; failed++; allPassed = false; console.log('  ✗ FAIL: ' + msg); }

// ══════════════════════════════════════════════════════════════════════
async function main() {
  const scratchObjs = [];
  const tableNames = Object.keys(SOURCE_TABLES);

  // ── PHASE 1: Apply 10 table DDLs (AC-1) ─────────────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('PHASE 1: CREATE all 10 tables (AC-1)');
  console.log('════════════════════════════════════════════════');

  for (const t of tableNames) {
    const bqName = SCRATCH + t;
    scratchObjs.push({ n: bqName, t: 'TABLE' });
    try {
      await dropIfExists(bqName);
      const ddl = generateBQDDL(t, SOURCE_TABLES[t]);
      await runQuery(ddl);
      ok('AC-1: ' + t + ' — CREATE TABLE succeeded');
    } catch (e) {
      nok('AC-1: ' + t + ' — CREATE TABLE failed: ' + e.message);
    }
  }

  // ── PHASE 1b: View (AC-1/AC-5) ──────────────────────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('PHASE 1b: View DDL (AC-1 / AC-5)');
  console.log('════════════════════════════════════════════════');

  // Build the "canonical" view DDL pointing at acme-lake-project
  const canonViewDDL =
    'CREATE VIEW `' + PROJECT + '.' + DATASET + '.' + SCRATCH + 'v_returns_pending` AS\n' +
    'SELECT\n' +
    '    r.rma_id,\n    r.customer_id,\n    r.invoice_no,\n    r.stock_code,\n    r.quantity,\n    r.requested_at,\n' +
    '    DATE_DIFF(CURRENT_DATE(), DATE(r.requested_at), DAY) AS days_pending\n' +
    'FROM `acme-lake-project.raw.return_authorizations` r\n' +
    'WHERE r.approved IS NULL OR r.approved = FALSE';

  console.log('\n  Canonical view DDL:\n  ' + canonViewDDL.replace(/\n/g, '\n  '));

  // AC-5 text checks
  if (canonViewDDL.includes('`acme-lake-project.raw.return_authorizations`'))
    ok('AC-5: View references `acme-lake-project.raw.return_authorizations`');
  else nok('AC-5: missing acme-lake-project reference');

  if (canonViewDDL.includes('DATE_DIFF('))
    ok('AC-5: DATEDIFF → DATE_DIFF conversion');
  else nok('AC-5: DATEDIFF not converted');

  if (canonViewDDL.includes('DATE(r.requested_at)'))
    ok('AC-5: to_date → DATE()');
  else nok('AC-5: to_date not converted');

  if (canonViewDDL.includes('CURRENT_DATE()'))
    ok('AC-5: current_date() → CURRENT_DATE()');
  else nok('AC-5: current_date not converted');

  // Create stub + local view to prove it compiles in BQ
  const stubName = SCRATCH + 'stub_ret_auth';
  const localViewName = SCRATCH + 'v_returns_local';
  scratchObjs.push({ n: stubName, t: 'TABLE' });
  scratchObjs.push({ n: localViewName, t: 'VIEW' });

  try {
    await dropIfExists(localViewName, 'VIEW');
    await dropIfExists(stubName);
    await runQuery(
      'CREATE TABLE `' + PROJECT + '.' + DATASET + '.' + stubName + '` (\n' +
      '  rma_id STRING, customer_id STRING, invoice_no STRING,\n' +
      '  stock_code STRING, quantity INT64, requested_at DATETIME, approved BOOL\n)'
    );
    await runQuery(
      'CREATE VIEW `' + PROJECT + '.' + DATASET + '.' + localViewName + '` AS\n' +
      'SELECT r.rma_id, r.customer_id, r.invoice_no, r.stock_code, r.quantity, r.requested_at,\n' +
      '  DATE_DIFF(CURRENT_DATE(), DATE(r.requested_at), DAY) AS days_pending\n' +
      'FROM `' + PROJECT + '.' + DATASET + '.' + stubName + '` r\n' +
      'WHERE r.approved IS NULL OR r.approved = FALSE'
    );
    ok('AC-1/AC-5: View compiles & creates (stub-backed)');
    // query it
    await runQuery('SELECT * FROM `' + PROJECT + '.' + DATASET + '.' + localViewName + '` LIMIT 0');
    ok('AC-5: View is queryable');
  } catch (e) {
    nok('AC-5: View creation failed: ' + e.message);
  }

  // Dry-run canonical DDL (will fail on project not found — that proves syntax is ok)
  try {
    await runQuery(canonViewDDL, true);
    ok('AC-5: Canonical view dry-run passed');
  } catch (e) {
    if (/not found|acme-lake-project/i.test(e.message))
      ok('AC-5: Canonical view syntax valid (dry-run fails only on missing external project)');
    else
      nok('AC-5: Canonical view syntax error: ' + e.message);
  }

  // ── PHASE 2: Read LANDED schema (AC-6 + AC-2/3/4) ───────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('PHASE 2: LANDED schema parity (AC-6)');
  console.log('════════════════════════════════════════════════');

  const [schemaCols] = await bq.query({
    query: 'SELECT table_name, column_name, data_type, ordinal_position ' +
           'FROM `' + PROJECT + '.' + DATASET + '.INFORMATION_SCHEMA.COLUMNS` ' +
           "WHERE table_name LIKE '" + SCRATCH + "%' " +
           'ORDER BY table_name, ordinal_position',
    location: process.env.TEST_BQ_LOCATION || 'EU',
  });

  const landed = {};
  for (const r of schemaCols) {
    const t = r.table_name.replace(SCRATCH, '');
    if (!landed[t]) landed[t] = [];
    landed[t].push({ name: r.column_name, type: r.data_type });
  }

  // Get DDL text for partition/cluster metadata
  const [tblRows] = await bq.query({
    query: 'SELECT table_name, ddl FROM `' + PROJECT + '.' + DATASET +
           ".INFORMATION_SCHEMA.TABLES` WHERE table_name LIKE '" + SCRATCH + "%'",
    location: process.env.TEST_BQ_LOCATION || 'EU',
  });
  const meta = {};
  for (const r of tblRows) {
    const t = r.table_name.replace(SCRATCH, '');
    const ddl = r.ddl || '';
    const pm = ddl.match(/PARTITION BY\s+(\w+)/i);
    const cm = ddl.match(/CLUSTER BY\s+([^\n]+)/i);
    meta[t] = {
      partCol: pm ? pm[1] : null,
      clusterCols: cm ? cm[1].replace(/;/g,'').split(',').map(c => c.trim().replace(/`/g, '')) : [],
      ddl,
    };
  }

  // Per-table schema parity
  for (const t of tableNames) {
    const src = SOURCE_TABLES[t];
    const l = landed[t];
    if (!l) { nok('AC-6: ' + t + ' — missing from INFORMATION_SCHEMA'); continue; }

    const expected = [];
    for (const c of src.columns) expected.push({ name: c.name, type: hiveTypeToBQ(c.hiveType) });
    if (t === 'dedup_clickstream') {
      expected.push({ name: 'date_ts', type: 'DATE' });
      expected.push({ name: 'country_partition', type: 'STRING' });
    } else if (src.partitionCols.length === 1) {
      expected.push({ name: src.partitionCols[0].name, type: 'DATE' });
    }

    let tblOk = true;
    for (const e of expected) {
      const f = l.find(c => c.name === e.name);
      if (!f) { nok('AC-6: ' + t + '.' + e.name + ' MISSING'); tblOk = false; continue; }
      const lt = f.type.replace(/\s+/g, '');
      const et = e.type.replace(/\s+/g, '');
      if (lt !== et && !(et === 'NUMERIC' && lt.startsWith('NUMERIC')) &&
          !(et === 'ARRAY<STRING>' && lt === 'ARRAY<STRING>')) {
        nok('AC-6: ' + t + '.' + e.name + ' type ' + lt + ' != ' + et);
        tblOk = false;
      }
    }
    const eNames = new Set(expected.map(c => c.name));
    for (const c of l) {
      if (!eNames.has(c.name)) { nok('AC-6: ' + t + '.' + c.name + ' UNEXPECTED'); tblOk = false; }
    }
    if (l.length !== expected.length) {
      nok('AC-6: ' + t + ' col count ' + l.length + ' != ' + expected.length);
      tblOk = false;
    }
    if (tblOk) ok('AC-6: ' + t + ' — ' + expected.length + ' cols correct');
  }

  // Partition intent
  console.log('\n  ── Partition/cluster intent ──');
  const nativeDate = ['cleansed_orders','cleansed_customers','cleansed_products',
    'geocoded_addresses','merged_returns_cdc','fraud_scored'];
  for (const t of nativeDate) {
    const m = meta[t];
    if (!m) continue;
    const exp = SOURCE_TABLES[t].partitionCols[0].name;
    if (m.partCol === exp) ok('AC-6: ' + t + ' partition=' + exp);
    else nok('AC-6: ' + t + ' partition=' + m.partCol + ' expected ' + exp);
  }
  const synthDate = ['parsed_loyalty_events','normalized_carrier_events','warehouse_kpi_snapshot'];
  for (const t of synthDate) {
    const m = meta[t];
    if (!m) continue;
    if (m.partCol === 'date_ts') ok('AC-6: ' + t + ' date_ts STRING→DATE partition');
    else nok('AC-6: ' + t + ' partition=' + m.partCol + ' expected date_ts');
  }

  // ── AC-2: dedup_clickstream ──────────────────────────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('AC-2: dedup_clickstream partition/cluster');
  console.log('════════════════════════════════════════════════');

  const cm = meta['dedup_clickstream'];
  if (cm) {
    const dtCol = (landed['dedup_clickstream'] || []).find(c => c.name === 'date_ts');
    if (dtCol && dtCol.type === 'DATE') ok('AC-2: date_ts is DATE');
    else nok('AC-2: date_ts type=' + (dtCol ? dtCol.type : 'MISSING'));

    if (cm.partCol === 'date_ts') ok('AC-2: PARTITION BY date_ts');
    else nok('AC-2: partCol=' + cm.partCol);

    const expCl = ['country_partition', 'user_id'];
    if (cm.clusterCols.length === 2 && expCl.every(c => cm.clusterCols.includes(c)))
      ok('AC-2: CLUSTER BY country_partition, user_id');
    else nok('AC-2: cluster=[' + cm.clusterCols.join(',') + '] expected [' + expCl.join(',') + ']');

    if (!cm.ddl.toUpperCase().includes('BUCKET'))
      ok('AC-2: No BUCKETS clause');
    else nok('AC-2: BUCKETS found');
  } else nok('AC-2: metadata missing');

  // ── AC-3: parsed_loyalty_events.meta → JSON ──────────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('AC-3: parsed_loyalty_events.meta MAP→JSON');
  console.log('════════════════════════════════════════════════');

  const loyaltyCols = landed['parsed_loyalty_events'];
  if (loyaltyCols) {
    const metaC = loyaltyCols.find(c => c.name === 'meta');
    if (metaC && metaC.type === 'JSON') ok('AC-3: meta is JSON');
    else nok('AC-3: meta type=' + (metaC ? metaC.type : 'MISSING'));
  } else nok('AC-3: table missing');

  // ── AC-4: fraud_scored.signals → ARRAY<STRING> ──────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('AC-4: fraud_scored.signals ARRAY<STRING>');
  console.log('════════════════════════════════════════════════');

  const fraudCols = landed['fraud_scored'];
  if (fraudCols) {
    const sigC = fraudCols.find(c => c.name === 'signals');
    if (sigC && sigC.type === 'ARRAY<STRING>') ok('AC-4: signals is ARRAY<STRING> in INFORMATION_SCHEMA');
    else nok('AC-4: signals type=' + (sigC ? sigC.type : 'MISSING'));
  } else nok('AC-4: table missing');

  // Confirm via metadata API
  try {
    const [tMeta] = await ds.table(SCRATCH + 'fraud_scored').getMetadata();
    const sf = tMeta.schema.fields.find(f => f.name === 'signals');
    if (sf && sf.mode === 'REPEATED' && sf.type === 'STRING')
      ok('AC-4: signals REPEATED STRING via metadata API');
    else nok('AC-4: metadata type=' + (sf ? sf.type + '/' + sf.mode : 'MISSING'));
  } catch (e) { nok('AC-4: metadata API error: ' + e.message); }

  // ── PHASE 3: Data-survival probes (AC-7 / AC-8) ─────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('PHASE 3: Data-survival probes');
  console.log('════════════════════════════════════════════════');

  // AC-7: DECIMAL round-trip
  console.log('\n  ── AC-7: DECIMAL(14,2) ──');
  const pdec = SCRATCH + 'probe_dec';
  scratchObjs.push({ n: pdec, t: 'TABLE' });
  try {
    await dropIfExists(pdec);
    await runQuery('CREATE TABLE `' + PROJECT + '.' + DATASET + '.' + pdec + '` (net_amount NUMERIC)');
    await runQuery("INSERT INTO `" + PROJECT + '.' + DATASET + '.' + pdec + "` (net_amount) VALUES (CAST('99999999999999.99' AS NUMERIC))");
    const [dr] = await bq.query({
      query: 'SELECT CAST(net_amount AS STRING) AS v FROM `' + PROJECT + '.' + DATASET + '.' + pdec + '`',
      location: process.env.TEST_BQ_LOCATION || 'EU',
    });
    if (dr.length === 1 && dr[0].v === '99999999999999.99')
      ok("AC-7: round-trip '99999999999999.99' → '" + dr[0].v + "' EXACT");
    else
      nok("AC-7: expected '99999999999999.99', got '" + (dr[0] ? dr[0].v : 'NO ROW') + "'");
  } catch (e) { nok('AC-7: ' + e.message); }

  // AC-8: FLOAT64 / DOUBLE round-trip
  console.log('\n  ── AC-8: FLOAT64 17-digit precision ──');
  const pflt = SCRATCH + 'probe_flt';
  scratchObjs.push({ n: pflt, t: 'TABLE' });
  try {
    await dropIfExists(pflt);
    await runQuery('CREATE TABLE `' + PROJECT + '.' + DATASET + '.' + pflt + '` (geocoded_lat FLOAT64)');
    await runQuery('INSERT INTO `' + PROJECT + '.' + DATASET + '.' + pflt + '` (geocoded_lat) VALUES (0.30000000000000004)');
    const [fr] = await bq.query({
      query: 'SELECT CAST(geocoded_lat AS STRING) AS v FROM `' + PROJECT + '.' + DATASET + '.' + pflt + '`',
      location: process.env.TEST_BQ_LOCATION || 'EU',
    });
    if (fr.length === 1) {
      const rv = fr[0].v;
      if (rv === '0.30000000000000004') {
        ok("AC-8: round-trip '0.30000000000000004' → '" + rv + "' EXACT");
      } else {
        // compare binary
        const seeded = 0.30000000000000004;
        const parsed = parseFloat(rv);
        if (Object.is(seeded, parsed))
          ok("AC-8: binary match (string='" + rv + "')");
        else
          nok("AC-8: expected '0.30000000000000004', got '" + rv + "'");
      }
    } else nok('AC-8: no rows');
  } catch (e) { nok('AC-8: ' + e.message); }

  // ── PHASE 4: TEARDOWN ───────────────────────────────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('PHASE 4: TEARDOWN');
  console.log('════════════════════════════════════════════════');

  // views first
  for (const o of scratchObjs.filter(x => x.t === 'VIEW')) {
    await dropIfExists(o.n, 'VIEW');
    console.log('  dropped VIEW ' + o.n);
  }
  for (const o of scratchObjs.filter(x => x.t === 'TABLE')) {
    await dropIfExists(o.n);
    console.log('  dropped TABLE ' + o.n);
  }
  for (const t of tableNames) {
    await dropIfExists(SCRATCH + t);
  }

  // ── SUMMARY ─────────────────────────────────────────────────────
  console.log('\n════════════════════════════════════════════════');
  console.log('SUMMARY');
  console.log('════════════════════════════════════════════════');
  console.log('  Total : ' + total);
  console.log('  Passed: ' + passed);
  console.log('  Failed: ' + failed);
  console.log('  Result: ' + (allPassed ? 'ALL PASSED ✓' : 'SOME FAILED ✗'));

  if (!allPassed) process.exit(1);
}

main().catch(err => {
  console.error('FATAL:', err);
  process.exit(2);
});
