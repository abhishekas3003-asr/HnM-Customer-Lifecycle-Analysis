-- ============================================================
-- 01_descriptive.sql
-- Question: what does the business look like at a glance —
--           how many customers, how often they buy, and whether
--           there's any seasonal pattern?
-- Key result: 67% repeat rate (the keystone number).
-- ============================================================


-- ---- Business size -------------------------------------------------

SELECT
    COUNT(*)                                AS total_items,
    COUNT(DISTINCT customer_id)             AS total_customers,
    COUNT(DISTINCT (customer_id, t_dat))    AS total_orders,
    SUM(price)                              AS total_spend      -- relative units
FROM raw_transactions;


-- ---- Repeat rate ---------------------------------------------------
-- Share of customers with 2+ orders. The single most important
-- descriptive figure — it tells us cohort/churn/CLV models are viable.

SELECT
    AVG(CASE WHEN total_orders >= 2 THEN 1.0 ELSE 0.0 END) AS repeat_rate
FROM customer_spine;


-- ---- Orders-per-customer distribution ------------------------------
-- Long-tailed: most customers cluster at 1-2 orders, a thin tail buys often.

SELECT
    total_orders,
    COUNT(customer_id) AS customers
FROM customer_spine
GROUP BY total_orders
ORDER BY total_orders;


-- ---- Basket size & spend per order ---------------------------------

SELECT
    COUNT(*) * 1.0 / COUNT(DISTINCT (customer_id, t_dat))       AS avg_items_per_order,
    SUM(price) * 1.0 / COUNT(DISTINCT (customer_id, t_dat))     AS avg_spend_per_order
FROM raw_transactions;


-- ---- Trend over time -----------------------------------------------
-- Monthly orders and spend. Shows summer peaks and a Mar-Apr 2020 dip
-- that coincides with COVID (association, not cause — end months are partial).

SELECT
    DATE_TRUNC('month', t_dat)              AS month,
    COUNT(DISTINCT (customer_id, t_dat))    AS orders,
    SUM(price)                              AS spend
FROM raw_transactions
GROUP BY DATE_TRUNC('month', t_dat)
ORDER BY month;
