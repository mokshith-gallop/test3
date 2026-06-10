-- ============================================================================
-- 00-dataset.sql
-- BigQuery dataset creation for the Acme Retail dimensional warehouse.
-- Source: 03-retail-tables.hql (CREATE DATABASE retail)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS `acme-analytics-project.retail`
OPTIONS (
  description = 'Acme retail dimensional warehouse: facts, dims, ACID returns, BI views',
  location = 'US'
);
