-- ============================================================
-- 03_churn.sql
-- Question: which customers have effectively left — and does the
--           churn rate depend on how we define "left"?
-- Method: derive the churn window from the data (repurchase-gap
--         distribution) rather than assuming a round number.
-- Key result: churn = 45.5% at 180 days (p95-derived), 61.5% at 90 days.
-- ============================================================


-- ---- Repurchase gap per customer -----------------------------------
-- Gap between consecutive orders, using LAG over each customer's
-- order dates. This is the raw material for the churn threshold.

WITH per_order AS (
    SELECT DISTINCT customer_id, t_dat       -- collapse articles to orders
    FROM raw_transactions
)
SELECT
    customer_id,
    t_dat AS order_date,
    LAG(t_dat) OVER (PARTITION BY customer_id ORDER BY t_dat)          AS previous_order_date,
    t_dat - LAG(t_dat) OVER (PARTITION BY customer_id ORDER BY t_dat)  AS gap
FROM per_order;


-- ---- Gap distribution → the churn threshold ------------------------
-- No natural "churned" line exists in transaction data, so we derive one.
-- p95 = 188 days: a customer past the 95th percentile of normal
-- repurchase behaviour has behaved abnormally. Rounded to a 180-day
-- window for a clean six-month business read.

WITH per_order AS (
    SELECT DISTINCT customer_id, t_dat
    FROM raw_transactions
),
gaps AS (
    SELECT
        t_dat - LAG(t_dat) OVER (PARTITION BY customer_id ORDER BY t_dat) AS gap
    FROM per_order
)
SELECT
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY gap) AS median_gap,   -- 22
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY gap) AS p90_gap,      -- 124
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY gap) AS p95_gap,      -- 188  <- threshold
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY gap) AS p99_gap       -- 364
FROM gaps;


-- ---- Overall churn rate --------------------------------------------
-- Recency = days since last purchase, measured from the dataset's
-- max date (derived, not hardcoded). Report both windows: the 180-day
-- primary and the 90-day sensitivity.

SELECT
    AVG(CASE WHEN recency > 180 THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_180,   -- 45.5
    AVG(CASE WHEN recency > 90  THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_90     -- 61.5
FROM (
    SELECT
        customer_id,
        (SELECT MAX(t_dat) FROM raw_transactions) - last_transaction AS recency
    FROM customer_spine
) AS t;


-- ---- Churn by membership status ------------------------------------
-- Association, not cause: pre-create members self-select, so their
-- higher churn reflects who they are, not the membership itself.

WITH segment AS (
    SELECT
        rc.club_member_status,
        rc.age,
        (SELECT MAX(t_dat) FROM raw_transactions) - cs.last_transaction AS recency
    FROM raw_customers rc
    JOIN customer_spine cs
        ON rc.customer_id = cs.customer_id
)
SELECT
    club_member_status,
    COUNT(*)                                                 AS segment_size,
    AVG(CASE WHEN recency > 180 THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_180,
    AVG(CASE WHEN recency > 90  THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_90
FROM segment
GROUP BY club_member_status;


-- ---- Churn by age band ---------------------------------------------
-- Nulls kept as 'Unknown' rather than dropped — and it paid off:
-- the Unknown-age group has a distinctly high churn rate (71.3%),
-- a signal a naive cleanup would have thrown away.

WITH segment AS (
    SELECT
        rc.age,
        (SELECT MAX(t_dat) FROM raw_transactions) - cs.last_transaction AS recency
    FROM raw_customers rc
    JOIN customer_spine cs
        ON rc.customer_id = cs.customer_id
)
SELECT
    CASE
        WHEN age BETWEEN 16 AND 25 THEN '16-25'
        WHEN age BETWEEN 26 AND 35 THEN '26-35'
        WHEN age BETWEEN 36 AND 45 THEN '36-45'
        WHEN age BETWEEN 46 AND 55 THEN '46-55'
        WHEN age BETWEEN 56 AND 65 THEN '56-65'
        WHEN age >= 66             THEN '66+'
        ELSE 'Unknown'
    END                                                     AS age_band,
    COUNT(*)                                                AS segment_size,
    AVG(CASE WHEN recency > 180 THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_180,
    AVG(CASE WHEN recency > 90  THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_90
FROM segment
GROUP BY 1
ORDER BY 1;
