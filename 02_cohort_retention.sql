-- ============================================================
-- 02_cohort_retention.sql
-- Question: once customers are acquired, how fast and how far
--           do they drop off — and does retention ever stabilise?
-- Produces: cohort_retention table (one row per cohort x month_offset).
-- Key result: first-month retention ~16% (2019), stabilising ~13%.
-- ============================================================


-- ---- Cohort retention table ----------------------------------------
-- Three-step pipeline:
--   offset_table : each purchase's months-since-first-purchase
--   cohort_counts: distinct actives per cohort per offset
--   size_of_cohort: each cohort's starting size (offset 0 baseline)

DROP TABLE IF EXISTS cohort_retention;

CREATE TABLE cohort_retention AS

WITH offset_table AS (
    SELECT
        customer_id,
        cohort_month,
        purchase_month,
        (
            (EXTRACT(YEAR  FROM purchase_month) - EXTRACT(YEAR  FROM cohort_month)) * 12
          + (EXTRACT(MONTH FROM purchase_month) - EXTRACT(MONTH FROM cohort_month))
        ) AS month_offset
    FROM (
        SELECT
            rt.customer_id,
            DATE_TRUNC('month', rt.t_dat)               AS purchase_month,
            DATE_TRUNC('month', cs.first_transaction)   AS cohort_month
        FROM raw_transactions rt
        JOIN customer_spine cs
            ON rt.customer_id = cs.customer_id
    ) AS t
),

cohort_counts AS (
    SELECT
        cohort_month,
        month_offset,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM offset_table
    GROUP BY cohort_month, month_offset
),

size_of_cohort AS (
    SELECT
        DATE_TRUNC('month', first_transaction)  AS cohort_month,
        COUNT(customer_id)                      AS cohort_size
    FROM customer_spine
    GROUP BY DATE_TRUNC('month', first_transaction)
)

SELECT
    cc.cohort_month,
    cc.month_offset,
    cc.active_customers,
    sc.cohort_size,
    (cc.active_customers * 1.0 / sc.cohort_size) * 100 AS retention_rate
FROM cohort_counts cc
JOIN size_of_cohort sc
    ON cc.cohort_month = sc.cohort_month
ORDER BY cc.cohort_month, cc.month_offset;


-- Add cohort_year for the dashboard year slicer.
ALTER TABLE cohort_retention ADD COLUMN cohort_year INT;
UPDATE cohort_retention SET cohort_year = EXTRACT(YEAR FROM cohort_month);


-- Reconciliation: offset 0 must equal 100% for every cohort.
SELECT cohort_month, retention_rate
FROM cohort_retention
WHERE month_offset = 0
ORDER BY cohort_month;


-- ============================================================
-- VALIDATION — retention figures and censoring
-- These checks are why the reported numbers are 16%/13% and not
-- an over-optimistic early read. Kept deliberately.
-- ============================================================

-- Per-cohort first-month retention (2019). Reveals a real decline
-- across the year: H1 cohorts (~18-20%) retain better than H2 (~13-16%).
SELECT cohort_month, cohort_size, active_customers, retention_rate
FROM cohort_retention
WHERE month_offset = 1
  AND cohort_year = 2019
ORDER BY cohort_month;

-- First-month retention two ways. They agree (16.4 vs 16.9),
-- so the choice of average doesn't change the story.
SELECT ROUND(AVG(retention_rate), 2) AS unweighted_avg
FROM cohort_retention
WHERE month_offset = 1 AND cohort_year = 2019;

SELECT ROUND(SUM(active_customers)::numeric / SUM(cohort_size) * 100, 2) AS pooled_retention
FROM cohort_retention
WHERE month_offset = 1 AND cohort_year = 2019;

-- Right-censoring check: which 2019 cohorts actually have a complete
-- 6-12 month window? Data ends Sep 2020, so Oct-Dec 2019 are incomplete.
SELECT cohort_month,
       COUNT(*)          AS offsets_present,
       MIN(month_offset) AS min_off,
       MAX(month_offset) AS max_off
FROM cohort_retention
WHERE cohort_year = 2019
  AND month_offset BETWEEN 6 AND 12
GROUP BY cohort_month
ORDER BY cohort_month;

-- Stabilised retention using ONLY cohorts with a full 6-12 window
-- (COUNT = 7). Excludes the censored Oct-Dec cohorts. Result: ~13%.
WITH complete AS (
    SELECT cohort_month
    FROM cohort_retention
    WHERE cohort_year = 2019
      AND month_offset BETWEEN 6 AND 12
    GROUP BY cohort_month
    HAVING COUNT(*) = 7
)
SELECT ROUND(AVG(retention_rate), 2) AS stabilized_complete_only
FROM cohort_retention
WHERE month_offset BETWEEN 6 AND 12
  AND cohort_month IN (SELECT cohort_month FROM complete);

-- Note on left-censoring: the earliest cohorts (Sep/Oct 2018) show
-- inflated opening retention (44%/36%) because the data starts
-- mid-stream. They are flagged as artefacts, not trends.
