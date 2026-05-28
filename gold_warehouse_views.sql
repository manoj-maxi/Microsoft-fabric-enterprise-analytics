-- =====================================================================
-- Gold Warehouse Views  (Fabric Warehouse SQL endpoint)
-- Business-friendly views over Gold Delta tables for paginated reports
-- and ad-hoc SQL. The Direct Lake semantic model reads the base tables;
-- these views serve Report Builder / SSRS-style consumption.
-- =====================================================================

-- Revenue by business unit and month (regulatory paginated report source)
CREATE OR ALTER VIEW gold.vw_revenue_by_bu_month AS
SELECT
    d.year_month,
    d.year,
    d.quarter,
    f.business_unit,
    f.currency,
    COUNT(DISTINCT f.invoice_id)        AS invoice_count,
    SUM(f.invoice_amount)               AS total_revenue,
    AVG(f.invoice_amount)               AS avg_line_amount
FROM gold.fact_revenue       f
JOIN gold.dim_date           d ON f.date_key = d.date_key
GROUP BY d.year_month, d.year, d.quarter, f.business_unit, f.currency;
GO

-- Revenue leakage candidate view: billed revenue vs rated usage variance
CREATE OR ALTER VIEW gold.vw_revenue_leakage AS
WITH billed AS (
    SELECT customer_sk, date_key, SUM(invoice_amount) AS billed_amt
    FROM gold.fact_revenue
    GROUP BY customer_sk, date_key
),
rated AS (
    SELECT customer_sk, date_key, SUM(rated_amount) AS rated_amt
    FROM gold.fact_usage
    GROUP BY customer_sk, date_key
)
SELECT
    c.customer_name,
    c.business_unit,
    dd.year_month,
    b.billed_amt,
    r.rated_amt,
    (r.rated_amt - b.billed_amt)                              AS leakage_amt,
    CASE WHEN r.rated_amt = 0 THEN 0
         ELSE (r.rated_amt - b.billed_amt) * 1.0 / r.rated_amt
    END                                                       AS leakage_pct
FROM rated r
JOIN billed b           ON r.customer_sk = b.customer_sk AND r.date_key = b.date_key
JOIN gold.dim_customer  c ON r.customer_sk = c.customer_sk AND c.is_current = 1
JOIN gold.dim_date      dd ON r.date_key = dd.date_key
WHERE (r.rated_amt - b.billed_amt) > 0;          -- under-billing only
GO

-- Cost assurance: vendor settlement summary
CREATE OR ALTER VIEW gold.vw_cost_by_vendor AS
SELECT
    v.vendor_name,
    d.year_month,
    SUM(f.settlement_amount) AS total_cost,
    COUNT(*)                 AS settlement_lines
FROM gold.fact_cost   f
JOIN gold.dim_vendor  v ON f.vendor_sk = v.vendor_sk
JOIN gold.dim_date    d ON f.date_key  = d.date_key
GROUP BY v.vendor_name, d.year_month;
GO
