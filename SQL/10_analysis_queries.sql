
USE ne_housing;
GO


WITH region_year AS (
    SELECT DISTINCT d.year_num,
           COUNT(*) OVER (PARTITION BY d.year_num) AS sales,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) OVER (PARTITION BY d.year_num) AS median_price
    FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key
)
SELECT year_num, sales, CAST(median_price AS INT) AS median_price,
       CAST(100.0 * median_price / FIRST_VALUE(median_price) OVER (ORDER BY year_num) AS DECIMAL(6,1)) AS index_first_year_100,
       CAST(100.0 * (median_price - LAG(median_price) OVER (ORDER BY year_num))
            / LAG(median_price) OVER (ORDER BY year_num) AS DECIMAL(5,2)) AS yoy_pct
FROM region_year
ORDER BY year_num;
GO

SELECT district_name, year_num, sales_count, median_price, prev_year_median, yoy_pct
FROM dw.v_district_year
WHERE is_partial_year = 0
ORDER BY district_name, year_num;
GO


SELECT growth_rank, district_name, sub_region, start_year, end_year, start_price, end_price, total_growth_pct, cagr_pct
FROM dw.v_district_growth_rank
ORDER BY growth_rank;
GO


WITH roll AS (
    SELECT r.location_key, r.month_start, r.median_price_12m, r.sales_12m,
           LAG(r.median_price_12m, 12) OVER (PARTITION BY r.location_key ORDER BY r.month_start) AS median_12m_ago
    FROM dw.agg_district_rolling12 r
)
SELECT l.district_name, roll.month_start, roll.median_price_12m, roll.median_12m_ago,
       CAST(100.0 * (roll.median_price_12m - roll.median_12m_ago) / NULLIF(roll.median_12m_ago, 0) AS DECIMAL(5,1)) AS change_pct,
       roll.sales_12m
FROM roll JOIN dw.dim_location l ON l.location_key = roll.location_key
WHERE roll.month_start = (SELECT MAX(month_start) FROM dw.agg_district_rolling12)
ORDER BY change_pct DESC;
GO

DECLARE @year INT = 2025;  
SELECT DISTINCT l.district_name, pt.type_name,
       COUNT(*) OVER (PARTITION BY l.district_name, pt.type_name) AS sales,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price)
            OVER (PARTITION BY l.district_name, pt.type_name) AS INT) AS median_price
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
JOIN dw.dim_location l ON l.location_key = f.location_key
JOIN dw.dim_property_type pt ON pt.property_type_key = f.property_type_key
WHERE d.year_num = @year
ORDER BY l.district_name, median_price DESC;
GO


DECLARE @year INT = 2025;
WITH m AS (
    SELECT DISTINCT l.district_name, f.build_status,
           COUNT(*) OVER (PARTITION BY l.district_name, f.build_status) AS sales,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price)
               OVER (PARTITION BY l.district_name, f.build_status) AS median_price
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    JOIN dw.dim_location l ON l.location_key = f.location_key
    WHERE d.year_num = @year AND f.build_status IS NOT NULL
)
SELECT n.district_name,
       n.sales AS new_build_sales, CAST(n.median_price AS INT) AS new_build_median,
       e.sales AS existing_sales,  CAST(e.median_price AS INT) AS existing_median,
       CAST(100.0 * (n.median_price - e.median_price) / e.median_price AS DECIMAL(5,1)) AS new_build_premium_pct
FROM m n
JOIN m e ON e.district_name = n.district_name AND e.build_status = 'Existing'
WHERE n.build_status = 'New build' AND n.sales >= 20    
ORDER BY new_build_premium_pct DESC;
GO


SELECT DISTINCT f.energy_rating,
       COUNT(*) OVER (PARTITION BY f.energy_rating) AS sales,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price_per_sqm)
            OVER (PARTITION BY f.energy_rating) AS INT) AS median_price_per_sqm
FROM dw.fact_sales f
WHERE f.price_per_sqm IS NOT NULL
ORDER BY f.energy_rating;
GO


SELECT l.district_name, a.ratio_year, a.price_earnings_ratio,
       RANK() OVER (PARTITION BY a.ratio_year ORDER BY a.price_earnings_ratio) AS affordability_rank_1_most_affordable,
       a.price_earnings_ratio - FIRST_VALUE(a.price_earnings_ratio)
            OVER (PARTITION BY a.location_key ORDER BY a.ratio_year) AS change_since_first_year
FROM dw.fact_affordability a
JOIN dw.dim_location l ON l.location_key = a.location_key
ORDER BY a.ratio_year DESC, affordability_rank_1_most_affordable;
GO

WITH p AS (
    SELECT DISTINCT f.postcode_district,
           COUNT(*) OVER (PARTITION BY f.postcode_district) AS sales,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price_per_sqm)
               OVER (PARTITION BY f.postcode_district) AS median_ppsm
    FROM dw.fact_sales f
    WHERE f.price_per_sqm IS NOT NULL AND f.postcode_district IS NOT NULL
)
SELECT postcode_district, sales, CAST(median_ppsm AS INT) AS median_price_per_sqm,
       NTILE(4) OVER (ORDER BY median_ppsm) AS price_quartile
FROM p
WHERE sales >= 50
ORDER BY median_ppsm DESC;
GO


WITH monthly AS (
    SELECT d.year_num, d.month_num, d.month_short, COUNT(*) AS sales
    FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key
    WHERE d.year_num BETWEEN 2016 AND 2025    
    GROUP BY d.year_num, d.month_num, d.month_short
)
SELECT month_num, month_short, AVG(sales) AS avg_sales_per_year
FROM monthly GROUP BY month_num, month_short ORDER BY month_num;
GO
