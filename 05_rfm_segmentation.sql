-- ============================================================
-- 05_rfm_segmentation.sql
-- Question: which customer groups should the business act on,
--           and what's the single highest-return target?
-- Method: adapted RFM. Frequency can't support 5 honest tiers
--         (a third of customers buy once), so the model is built on
--         Recency x Monetary, with one-time buyers split out.
-- Key result: At-Risk = 10,755 customers, 10.8% of revenue, 66% churn.
-- ============================================================


-- ---- Why frequency was dropped -------------------------------------
-- Check: NTILE(5) on total_orders collapses because one-time buyers
-- pile up at the bottom — the tiers aren't meaningfully distinct.
-- This is the evidence behind the R x M decision.

WITH rfm_base AS (
    SELECT customer_id, total_orders,
           NTILE(5) OVER (ORDER BY total_orders) AS f_score
    FROM customer_spine
)
SELECT f_score, MIN(total_orders), MAX(total_orders), COUNT(*)
FROM rfm_base
GROUP BY f_score
ORDER BY f_score;


-- ---- RFM segments (Recency x Monetary) -----------------------------
-- Repeat buyers only (total_orders >= 2). Recency is inverted in the
-- NTILE (ORDER BY recency DESC) so that r_score 5 = most recent.
-- One-time buyers are added separately below.

CREATE TABLE rfm_segments AS
WITH scored AS (
    SELECT
        customer_id,
        total_orders,
        total_spend,
        (SELECT MAX(t_dat) FROM raw_transactions) - last_transaction AS recency,
        NTILE(5) OVER (
            ORDER BY ((SELECT MAX(t_dat) FROM raw_transactions) - last_transaction) DESC
        ) AS r_score,
        NTILE(5) OVER (ORDER BY total_spend) AS m_score
    FROM customer_spine
    WHERE total_orders >= 2
)
SELECT
    customer_id,
    r_score,
    m_score,
    CASE
        WHEN r_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score <= 2 AND m_score >= 4 THEN 'At-Risk'
        WHEN r_score <= 2 AND m_score <= 2 THEN 'Hibernating/Lost'
        WHEN r_score >= 3 AND m_score >= 3 THEN 'Loyal'
        ELSE 'Needs Attention'
    END AS segment
FROM scored;


-- ---- One-time buyers as their own segment --------------------------
-- Scored NULL, not 0 — a zero would corrupt segment averages; NULL
-- self-excludes. One-timers are a different business problem
-- (first-purchase conversion, not reactivation), so they stand alone.

INSERT INTO rfm_segments (customer_id, r_score, m_score, segment)
SELECT
    customer_id,
    NULL, NULL,
    'One-Timers'
FROM customer_spine
WHERE total_orders = 1;


-- ---- Segment sizes -------------------------------------------------

SELECT segment, COUNT(*) AS n
FROM rfm_segments
GROUP BY segment
ORDER BY n DESC;


-- ============================================================
-- VALIDATION — funnel nesting
-- The dashboard's lifecycle view treats the loyal core (Champions +
-- Loyal) as a subset of repeat buyers. Confirm every Champion and
-- Loyal customer actually is a repeat buyer (one_time_buyers = 0),
-- so the nesting is honest.
-- ============================================================

SELECT
    s.segment,
    COUNT(*)                                                  AS total_customers,
    SUM(CASE WHEN sp.total_orders > 1 THEN 1 ELSE 0 END)      AS repeat_buyers,
    SUM(CASE WHEN sp.total_orders = 1 THEN 1 ELSE 0 END)      AS one_time_buyers
FROM rfm_segments s
JOIN customer_spine sp ON s.customer_id = sp.customer_id
WHERE s.segment IN ('Champions', 'Loyal')
GROUP BY s.segment;

-- ---- rfm_scorecard (per-segment aggregate, feeds the dashboard) -----
-- rfm_segments joined back to spend/recency and aggregated per segment.
-- This is the exact table the Power BI segment scorecard reads from.

CREATE TABLE rfm_scorecard AS
WITH seg AS (
    SELECT
        s.segment,
        cs.total_spend,
        (SELECT MAX(t_dat) FROM raw_transactions) - cs.last_transaction AS recency,
        SUM(cs.total_spend) OVER () AS grand_total
    FROM rfm_segments s
    JOIN customer_spine cs ON s.customer_id = cs.customer_id
)
SELECT
    segment,
    COUNT(*)                                                 AS customers,
    AVG(CASE WHEN recency > 180 THEN 1.0 ELSE 0.0 END) * 100 AS churn_180,
    SUM(total_spend)                                         AS segment_value,
    (SUM(total_spend) / MAX(grand_total)) * 100             AS value_share_pct
FROM seg
GROUP BY segment
ORDER BY value_share_pct DESC;
