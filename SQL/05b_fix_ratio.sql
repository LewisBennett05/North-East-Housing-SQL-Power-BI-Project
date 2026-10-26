
USE ne_housing;
GO
SET NOCOUNT ON;

DECLARE @c1 NVARCHAR(128), @c2 NVARCHAR(128), @o1 INT, @o2 INT;
DECLARE @sql NVARCHAR(MAX), @vals NVARCHAR(MAX);
DECLARE @header_in_data BIT = 0, @hdrjoin NVARCHAR(MAX) = N'';


SELECT TOP 1 @c1 = COLUMN_NAME, @o1 = ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw'
  AND LOWER(COLUMN_NAME) LIKE '%local authority code%'
ORDER BY ORDINAL_POSITION;

IF @c1 IS NULL
    SELECT @c1 = COLUMN_NAME, @o1 = ORDINAL_POSITION
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw' AND ORDINAL_POSITION = 1;

SELECT TOP 1 @c2 = COLUMN_NAME, @o2 = ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw'
  AND LOWER(COLUMN_NAME) LIKE '%local authority name%'
ORDER BY ORDINAL_POSITION;

IF @c2 IS NULL
    SELECT @c2 = COLUMN_NAME, @o2 = ORDINAL_POSITION
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw' AND ORDINAL_POSITION = @o1 + 1;


SET @sql = N'SELECT @x = CASE WHEN EXISTS (SELECT 1 FROM staging.ratio_raw
                 WHERE LTRIM(RTRIM(CAST(' + QUOTENAME(@c1) + N' AS NVARCHAR(100)))) IN (N''Code'', N''Local authority code'')) THEN 1 ELSE 0 END;';
EXEC sp_executesql @sql, N'@x BIT OUTPUT', @x = @header_in_data OUTPUT;

IF @header_in_data = 1
    SET @hdrjoin = N'CROSS JOIN (SELECT TOP 1 * FROM staging.ratio_raw
                      WHERE LTRIM(RTRIM(CAST(' + QUOTENAME(@c1) + N' AS NVARCHAR(100)))) IN (N''Code'', N''Local authority code'')) h';


SELECT @vals = STRING_AGG(CAST(
         N'(' + CASE WHEN @header_in_data = 1
                     THEN N'CAST(h.' + QUOTENAME(COLUMN_NAME) + N' AS NVARCHAR(100))'
                     ELSE N'N''' + REPLACE(COLUMN_NAME, '''', '''''') + N'''' END
         + N', CAST(r.' + QUOTENAME(COLUMN_NAME) + N' AS NVARCHAR(100)))' AS NVARCHAR(MAX)), N',')
       WITHIN GROUP (ORDER BY ORDINAL_POSITION)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw'
  AND ORDINAL_POSITION > @o2
  AND (@header_in_data = 1 OR PATINDEX('%[12][0-9][0-9][0-9]%', COLUMN_NAME) > 0);


SELECT @c1 AS code_column_used, @c2 AS name_column_used, @header_in_data AS heading_row_was_in_data;

SELECT COLUMN_NAME AS year_columns_used
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw'
  AND ORDINAL_POSITION > @o2
  AND (@header_in_data = 1 OR PATINDEX('%[12][0-9][0-9][0-9]%', COLUMN_NAME) > 0)
ORDER BY ORDINAL_POSITION;

SET @sql = N'SELECT COUNT(*) AS districts_found_in_sheet FROM staging.ratio_raw r
             WHERE LTRIM(RTRIM(CAST(r.' + QUOTENAME(@c1) + N' AS NVARCHAR(100)))) IN (SELECT ons_code FROM clean.ref_district);';
EXEC (@sql);


TRUNCATE TABLE clean.ratio;

SET @sql = N'
INSERT clean.ratio (ons_code, ons_name, year_label, ratio_year, price_earnings_ratio)
SELECT LTRIM(RTRIM(CAST(r.' + QUOTENAME(@c1) + N' AS NVARCHAR(100)))),
       LTRIM(RTRIM(CAST(r.' + QUOTENAME(@c2) + N' AS NVARCHAR(100)))),
       LTRIM(RTRIM(v.year_label)),
       TRY_CAST(SUBSTRING(v.year_label, NULLIF(PATINDEX(''%[12][0-9][0-9][0-9]%'', v.year_label), 0), 4) AS INT),
       TRY_CAST(TRY_CAST(v.raw_value AS FLOAT) AS DECIMAL(9,3))
FROM staging.ratio_raw r ' + @hdrjoin + N'
CROSS APPLY (VALUES ' + @vals + N') AS v(year_label, raw_value)
WHERE LTRIM(RTRIM(CAST(r.' + QUOTENAME(@c1) + N' AS NVARCHAR(100)))) IN (SELECT ons_code FROM clean.ref_district)
  AND TRY_CAST(SUBSTRING(v.year_label, NULLIF(PATINDEX(''%[12][0-9][0-9][0-9]%'', v.year_label), 0), 4) AS INT) IS NOT NULL;';
EXEC (@sql);


TRUNCATE TABLE dw.fact_affordability;

INSERT dw.fact_affordability (location_key, ratio_year, date_key, price_earnings_ratio, source_label)
SELECT l.location_key, r.ratio_year, r.ratio_year * 10000 + 101, r.price_earnings_ratio, r.year_label
FROM clean.ratio r
JOIN dw.dim_location l ON l.ons_code = r.ons_code
WHERE r.ratio_year BETWEEN 2015 AND 2027
  AND r.price_earnings_ratio IS NOT NULL;
GO


SELECT COUNT(*) AS clean_ratio_rows FROM clean.ratio;
SELECT COUNT(*) AS fact_affordability_rows,
       MIN(ratio_year) AS first_year, MAX(ratio_year) AS last_year,
       COUNT(DISTINCT location_key) AS districts
FROM dw.fact_affordability;
SELECT TOP 12 l.district_name, a.ratio_year, a.price_earnings_ratio
FROM dw.fact_affordability a JOIN dw.dim_location l ON l.location_key = a.location_key
WHERE a.ratio_year = (SELECT MAX(ratio_year) FROM dw.fact_affordability)
ORDER BY a.price_earnings_ratio;
