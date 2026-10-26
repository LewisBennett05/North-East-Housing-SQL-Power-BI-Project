
USE ne_housing;
GO
DROP TABLE IF EXISTS dw.agg_district_month;
DROP TABLE IF EXISTS dw.agg_district_rolling12;


SELECT DISTINCT
       f.location_key,
       d.month_start,
       COUNT(*) OVER (PARTITION BY f.location_key, d.month_start)                       AS sales_count,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price)
            OVER (PARTITION BY f.location_key, d.month_start) AS DECIMAL(12,0))         AS median_price,
       CAST(AVG(CAST(f.price AS DECIMAL(18,2))) OVER (PARTITION BY f.location_key, d.month_start) AS DECIMAL(12,0)) AS mean_price
INTO dw.agg_district_month
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key;

ALTER TABLE dw.agg_district_month ALTER COLUMN location_key INT NOT NULL;
ALTER TABLE dw.agg_district_month ALTER COLUMN month_start DATE NOT NULL;
ALTER TABLE dw.agg_district_month ADD CONSTRAINT pk_agg_month PRIMARY KEY (location_key, month_start);
GO


DECLARE @min_date DATE = (SELECT MIN(d.full_date) FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key);
DECLARE @max_date DATE = (SELECT MAX(d.full_date) FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key);


DECLARE @first_month DATE = DATEADD(MONTH, 11, DATEFROMPARTS(YEAR(@min_date), MONTH(@min_date), 1));
DECLARE @last_month  DATE = DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(@max_date), MONTH(@max_date), 1));

;WITH months AS (
    SELECT full_date AS month_start
    FROM dw.dim_date
    WHERE day_of_month = 1 AND full_date BETWEEN @first_month AND @last_month
),
sales AS (
    SELECT f.location_key, f.price, d.full_date
    FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key
)
SELECT DISTINCT
       s.location_key,
       m.month_start,
       COUNT(*) OVER (PARTITION BY s.location_key, m.month_start)                    AS sales_12m,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price)
            OVER (PARTITION BY s.location_key, m.month_start) AS DECIMAL(12,0))      AS median_price_12m
INTO dw.agg_district_rolling12
FROM months m
JOIN sales  s ON s.full_date >= DATEADD(MONTH, -11, m.month_start)
             AND s.full_date <  DATEADD(MONTH,   1, m.month_start);

ALTER TABLE dw.agg_district_rolling12 ALTER COLUMN location_key INT NOT NULL;
ALTER TABLE dw.agg_district_rolling12 ALTER COLUMN month_start DATE NOT NULL;
ALTER TABLE dw.agg_district_rolling12 ADD CONSTRAINT pk_agg_roll12 PRIMARY KEY (location_key, month_start);
GO


CREATE OR ALTER VIEW dw.v_district_year AS
WITH annual AS (
    SELECT DISTINCT
           f.location_key,
           d.year_num,
           COUNT(*) OVER (PARTITION BY f.location_key, d.year_num) AS sales_count,
           CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price)
                OVER (PARTITION BY f.location_key, d.year_num) AS DECIMAL(12,0)) AS median_price
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
),
last_sale AS (
    SELECT MAX(d.full_date) AS last_date
    FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key
)
SELECT a.location_key,
       l.district_name,
       l.sub_region,
       a.year_num,
       a.sales_count,
       a.median_price,
       LAG(a.median_price) OVER (PARTITION BY a.location_key ORDER BY a.year_num) AS prev_year_median,
       CAST(100.0 * (a.median_price - LAG(a.median_price) OVER (PARTITION BY a.location_key ORDER BY a.year_num))
            / NULLIF(LAG(a.median_price) OVER (PARTITION BY a.location_key ORDER BY a.year_num), 0)
            AS DECIMAL(6,2)) AS yoy_pct,
       CASE WHEN a.year_num = YEAR(ls.last_date) AND ls.last_date < DATEFROMPARTS(a.year_num, 12, 25)
            THEN 1 ELSE 0 END AS is_partial_year
FROM annual a
JOIN dw.dim_location l ON l.location_key = a.location_key
CROSS JOIN last_sale ls;
GO


CREATE OR ALTER VIEW dw.v_district_growth_rank AS
WITH base AS (
    SELECT * FROM dw.v_district_year WHERE is_partial_year = 0
),
bounds AS (
    SELECT MIN(year_num) AS y0, MAX(year_num) AS y1 FROM base
),
g AS (
    SELECT s.location_key, s.district_name, s.sub_region,
           b.y0 AS start_year, b.y1 AS end_year,
           s.median_price AS start_price, e.median_price AS end_price
    FROM base s
    JOIN bounds b ON s.year_num = b.y0
    JOIN base   e ON e.location_key = s.location_key AND e.year_num = b.y1
)
SELECT location_key, district_name, sub_region, start_year, end_year, start_price, end_price,
       CAST(100.0 * (end_price - start_price) / start_price AS DECIMAL(6,1)) AS total_growth_pct,
       CAST(100.0 * (POWER(CAST(end_price AS FLOAT) / start_price, 1.0 / (end_year - start_year)) - 1) AS DECIMAL(5,2)) AS cagr_pct,
       RANK() OVER (ORDER BY (end_price - start_price) * 1.0 / start_price DESC) AS growth_rank
FROM g;
GO

SELECT * FROM dw.v_district_growth_rank ORDER BY growth_rank;
