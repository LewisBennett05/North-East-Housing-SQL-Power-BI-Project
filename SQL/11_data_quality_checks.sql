
USE ne_housing;
GO

SELECT 'staging.pp_raw (NE rows loaded)'   AS stage, COUNT(*) AS n FROM staging.pp_raw
UNION ALL SELECT 'clean.pp_typed (after de-dupe of IDs)', COUNT(*) FROM clean.pp_typed
UNION ALL SELECT 'clean.sales (valid)',                   COUNT(*) FROM clean.sales
UNION ALL SELECT 'dw.fact_sales',                         COUNT(*) FROM dw.fact_sales;



SELECT reject_reason, COUNT(*) AS n FROM clean.pp_typed WHERE reject_reason IS NOT NULL GROUP BY reject_reason ORDER BY n DESC;


SELECT transaction_id, COUNT(*) FROM dw.fact_sales GROUP BY transaction_id HAVING COUNT(*) > 1;


SELECT MIN(d.full_date) AS first_sale, MAX(d.full_date) AS last_sale,
       MIN(f.price) AS min_price, MAX(f.price) AS max_price
FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key;


SELECT l.district_name, COUNT(*) AS sales FROM dw.fact_sales f
JOIN dw.dim_location l ON l.location_key = f.location_key GROUP BY l.district_name ORDER BY 1;


SELECT SUM(CASE WHEN postcode IS NULL THEN 1 ELSE 0 END) AS no_postcode,
       CAST(100.0 * SUM(CASE WHEN postcode IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS pct
FROM dw.fact_sales;

SELECT COUNT(*) AS sales, SUM(CAST(epc_matched AS INT)) AS matched,
       CAST(100.0 * SUM(CAST(epc_matched AS INT)) / COUNT(*) AS DECIMAL(5,1)) AS match_pct
FROM dw.fact_sales;

SELECT d.year_num, COUNT(*) AS sales,
       CAST(100.0 * AVG(CAST(f.epc_matched AS FLOAT)) AS DECIMAL(5,1)) AS match_pct
FROM dw.fact_sales f JOIN dw.dim_date d ON d.date_key = f.date_key GROUP BY d.year_num ORDER BY d.year_num;

SELECT pt.type_name, COUNT(*) AS sales,
       CAST(100.0 * AVG(CAST(f.epc_matched AS FLOAT)) AS DECIMAL(5,1)) AS match_pct
FROM dw.fact_sales f JOIN dw.dim_property_type pt ON pt.property_type_key = f.property_type_key GROUP BY pt.type_name;

SELECT f.build_status, COUNT(*) AS sales,
       CAST(100.0 * AVG(CAST(f.epc_matched AS FLOAT)) AS DECIMAL(5,1)) AS match_pct
FROM dw.fact_sales f GROUP BY f.build_status;


SELECT MIN(price_per_sqm) AS min_ppsm, MAX(price_per_sqm) AS max_ppsm, AVG(price_per_sqm) AS avg_ppsm,
       SUM(CASE WHEN epc_matched = 1 AND price_per_sqm IS NULL THEN 1 ELSE 0 END) AS matched_but_ppsm_rejected
FROM dw.fact_sales;


SELECT l.district_name, COUNT(*) AS years, MIN(a.ratio_year) AS first_year, MAX(a.ratio_year) AS last_year
FROM dw.fact_affordability a JOIN dw.dim_location l ON l.location_key = a.location_key
GROUP BY l.district_name ORDER BY 1;


SELECT COUNT(*) AS orphan_dates FROM dw.fact_sales f LEFT JOIN dw.dim_date d ON d.date_key = f.date_key WHERE d.date_key IS NULL;
