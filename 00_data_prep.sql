-- ============================================================
-- 00_data_prep.sql
-- Question: what is the clean base every later figure is built on?
-- Produces: raw tables, article lookup, indexes, and customer_spine
--           (one row per customer). Ends with null checks so metadata
--           gaps are known, not discovered later.
-- ============================================================


-- ---- Raw tables ----------------------------------------------------

CREATE TABLE raw_transactions (
    t_dat            date,
    customer_id      text,
    article_id       bigint,
    price            numeric,        -- normalised, not currency (max ~0.59)
    sales_channel_id smallint
);

CREATE TABLE raw_customers (
    customer_id            text,
    fn                     numeric,
    active                 numeric,
    club_member_status     text,
    fashion_news_frequency text,
    age                    numeric,
    postal_code            text
);


-- articles.csv has ~25 columns. Load all into a staging table,
-- then keep only the 5 fields we actually slice by.
CREATE TABLE stg_articles (
    article_id                   bigint,
    product_code                 bigint,
    prod_name                    text,
    product_type_no              bigint,
    product_type_name            text,
    product_group_name           text,
    graphical_appearance_no      bigint,
    graphical_appearance_name    text,
    colour_group_code            bigint,
    colour_group_name            text,
    perceived_colour_value_id    bigint,
    perceived_colour_value_name  text,
    perceived_colour_master_id   bigint,
    perceived_colour_master_name text,
    department_no                bigint,
    department_name              text,
    index_code                   text,
    index_name                   text,
    index_group_no               bigint,
    index_group_name             text,
    section_no                   bigint,
    section_name                 text,
    garment_group_no             bigint,
    garment_group_name           text,
    detail_desc                  text
);

CREATE TABLE raw_articles AS
SELECT article_id, product_group_name, product_type_name,
       index_group_name, department_name
FROM stg_articles;

DROP TABLE stg_articles;


-- Indexes on the columns every join and window function uses.
CREATE INDEX ix_tx_customer ON raw_transactions (customer_id);
CREATE INDEX ix_tx_date     ON raw_transactions (t_dat);


-- ---- Sanity: scale of the working set ------------------------------

SELECT COUNT(*)                                  AS rows,
       COUNT(DISTINCT customer_id)               AS customers,
       COUNT(DISTINCT (customer_id, t_dat))      AS orders,   -- order = customer + date
       MIN(t_dat)                                AS first_day,
       MAX(t_dat)                                AS last_day
FROM raw_transactions;


-- ---- Null checks ---------------------------------------------------
-- Core transaction fields must be complete; metadata gaps are kept
-- as "Unknown" downstream rather than dropped (see 03_churn.sql).

SELECT
    COUNT(*)            AS total_rows,
    COUNT(customer_id)  AS non_null_customer_id,
    COUNT(t_dat)        AS non_null_t_dat,
    COUNT(price)        AS non_null_price
FROM raw_transactions;

SELECT
    COUNT(*)                        AS total_rows,
    COUNT(age)                      AS non_null_age,
    COUNT(club_member_status)       AS non_null_club_member_status,
    COUNT(fashion_news_frequency)   AS non_null_fashion_news_frequency
FROM raw_customers;


-- ---- Customer spine ------------------------------------------------
-- One row per customer. Grain note: raw_transactions is one row per
-- ARTICLE, so an "order" is a distinct (customer_id, t_dat) pair.

CREATE TABLE customer_spine AS
SELECT
    customer_id,
    COUNT(*)                    AS total_items,
    MIN(t_dat)                  AS first_transaction,
    MAX(t_dat)                  AS last_transaction,
    COUNT(DISTINCT t_dat)       AS total_orders,
    SUM(price)                  AS total_spend
FROM raw_transactions
GROUP BY customer_id;

SELECT COUNT(*) AS spine_rows FROM customer_spine;
