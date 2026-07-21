-- ============================================================
-- 04_clv.sql
-- Question: how concentrated is revenue, and do high-value
--           customers churn differently from low-value ones?
-- Produces: clv_deciles table (used by the Power BI dashboard).
-- Key result: top 10% of customers = 51% of revenue; churn falls
--             74% -> 6.4% across deciles; revenue-weighted churn = 17.9%.
-- ============================================================


-- ---- Value concentration by spend decile ---------------------------
-- NTILE(10) by total spend. value_share_pct shows how lopsided
-- revenue is — the top decile alone carries ~51%.

WITH decile_category AS (
    SELECT
        customer_id,
        total_spend,
        SUM(total_spend) OVER ()                    AS grand_total,
        NTILE(10) OVER (ORDER BY total_spend)       AS spend_decile
    FROM customer_spine
)
SELECT
    spend_decile,
    COUNT(customer_id)                              AS customers,
    SUM(total_spend)                                AS decile_spend,
    (SUM(total_spend) * 1.0 / AVG(grand_total)) * 100 AS value_share_pct
FROM decile_category
GROUP BY spend_decile
ORDER BY spend_decile DESC;


-- ---- Value x churn cross (the core insight) ------------------------
-- Churn measured WITHIN each spend decile. Falls monotonically from
-- 74% (D1) to 6.4% (D10) — the customers who leave are the ones who
-- spend least. Association, not cause: recency drives both.

WITH decile AS (
    SELECT
        customer_id,
        total_spend,
        NTILE(10) OVER (ORDER BY total_spend) AS spend_decile,
        (SELECT MAX(t_dat) FROM raw_transactions) - last_transaction AS recency
    FROM customer_spine
)
SELECT
    spend_decile,
    SUM(total_spend)                                        AS decile_spend,
    AVG(CASE WHEN recency > 180 THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_180,
    AVG(CASE WHEN recency > 90  THEN 1.0 ELSE 0.0 END) * 100 AS churn_rate_90
FROM decile
GROUP BY spend_decile
ORDER BY spend_decile;


-- ---- clv_deciles table (feeds the dashboard) -----------------------

CREATE TABLE clv_deciles AS
WITH decile AS (
    SELECT
        customer_id,
        total_spend,
        NTILE(10) OVER (ORDER BY total_spend)               AS spend_decile,
        (SELECT MAX(t_dat) FROM raw_transactions) - last_transaction AS recency,
        SUM(total_spend) OVER ()                            AS grand_total
    FROM customer_spine
)
SELECT
    spend_decile,
    COUNT(*)                                                AS customers,
    AVG(CASE WHEN recency > 180 THEN 1.0 ELSE 0.0 END) * 100 AS churn_180,
    AVG(CASE WHEN recency > 90  THEN 1.0 ELSE 0.0 END) * 100 AS churn_90,
    (SUM(total_spend) / MAX(grand_total)) * 100             AS value_share_pct
FROM decile
GROUP BY spend_decile
ORDER BY spend_decile;

-- Dashboard helper columns.
ALTER TABLE clv_deciles ADD COLUMN decile_label TEXT;
UPDATE clv_deciles SET decile_label = 'D' || spend_decile;

ALTER TABLE clv_deciles ADD COLUMN value_group TEXT;
UPDATE clv_deciles SET value_group =
    CASE
        WHEN spend_decile = 10 THEN 'Top decile'
        WHEN spend_decile = 9  THEN '9th decile'
        ELSE 'Bottom 80%'
    END;


-- ============================================================
-- VALIDATION — revenue-weighted churn (the headline number)
-- Weights each decile's churn by the revenue it carries. This is
-- the figure that proves the thesis: 45% of CUSTOMERS churn, but
-- only ~18% of REVENUE is at risk.
-- ============================================================

SELECT ROUND(SUM(churn_180 * value_share_pct) / SUM(value_share_pct), 1)
       AS revenue_weighted_churn        -- 17.9
FROM clv_deciles;
