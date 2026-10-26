
USE ne_housing;
GO

DECLARE @min_area DECIMAL(8,2) = 15;    
DECLARE @max_area DECIMAL(8,2) = 500;  

DROP TABLE IF EXISTS clean.epc;

;WITH t AS (
    SELECT
        LTRIM(RTRIM(lmk_key))                                  AS lmk_key,
        LTRIM(RTRIM(local_authority))                          AS ons_code,
        CAST(clean.fn_postcode_nospace(postcode) AS VARCHAR(20)) AS postcode_nospace,
        clean.fn_norm_text(address1)                           AS addr_key1,    
        clean.fn_norm_text(CONCAT_WS(' ', address1, address2)) AS addr_key12,   
        TRY_CAST(LEFT(lodgement_date, 10) AS DATE)             AS lodgement_date,
        TRY_CAST(total_floor_area AS DECIMAL(8,2))             AS floor_area_m2,
        UPPER(LTRIM(RTRIM(current_energy_rating)))             AS energy_rating,
        TRY_CAST(current_energy_efficiency AS INT)             AS energy_efficiency,
        property_type, built_form, construction_age_band, tenure,
        TRY_CAST(number_habitable_rooms AS INT)                AS habitable_rooms
    FROM staging.epc_raw
), d AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY lmk_key ORDER BY lodgement_date DESC) AS rn FROM t
)
SELECT lmk_key, ons_code, postcode_nospace, addr_key1, addr_key12, lodgement_date,
       floor_area_m2, energy_rating, energy_efficiency, property_type, built_form,
       construction_age_band, tenure, habitable_rooms
INTO clean.epc
FROM d
WHERE rn = 1
  AND floor_area_m2 BETWEEN @min_area AND @max_area
  AND energy_rating IN ('A','B','C','D','E','F','G')
  AND postcode_nospace IS NOT NULL
  AND LEN(postcode_nospace) BETWEEN 5 AND 7
  AND addr_key1 IS NOT NULL
  AND lodgement_date IS NOT NULL;

CREATE CLUSTERED INDEX cx_epc_postcode ON clean.epc (postcode_nospace);
CREATE INDEX ix_epc_lmk ON clean.epc (lmk_key);

SELECT (SELECT COUNT(*) FROM staging.epc_raw) AS epc_raw_rows,
       (SELECT COUNT(*) FROM clean.epc)       AS epc_clean_rows;
GO


DROP TABLE IF EXISTS clean.ratio;
CREATE TABLE clean.ratio (
    ons_code             CHAR(9)       NOT NULL,
    ons_name             VARCHAR(100)  NULL,
    year_label           VARCHAR(100)  NOT NULL,  
    ratio_year           INT           NULL,
    price_earnings_ratio DECIMAL(9,3)  NULL,
    CONSTRAINT pk_ratio PRIMARY KEY (ons_code, year_label)
);

DECLARE @code NVARCHAR(128), @name NVARCHAR(128), @vals NVARCHAR(MAX), @sql NVARCHAR(MAX);

SELECT @code = MAX(CASE WHEN ORDINAL_POSITION = 1 THEN COLUMN_NAME END),
       @name = MAX(CASE WHEN ORDINAL_POSITION = 2 THEN COLUMN_NAME END)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw';

SELECT @vals = STRING_AGG(
           CAST(N'(N''' + REPLACE(COLUMN_NAME, '''', '''''') + N''', CAST(r.' + QUOTENAME(COLUMN_NAME) + N' AS NVARCHAR(50)))' AS NVARCHAR(MAX)),
           N',') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw' AND ORDINAL_POSITION > 2;

SET @sql = N'
INSERT clean.ratio (ons_code, ons_name, year_label, ratio_year, price_earnings_ratio)
SELECT LTRIM(RTRIM(r.' + QUOTENAME(@code) + N')),
       LTRIM(RTRIM(r.' + QUOTENAME(@name) + N')),
       v.year_label,
       TRY_CAST(RIGHT(RTRIM(v.year_label), 4) AS INT),
       TRY_CAST(v.raw_value AS DECIMAL(9,3))
FROM staging.ratio_raw r
CROSS APPLY (VALUES ' + @vals + N') AS v(year_label, raw_value)
WHERE LTRIM(RTRIM(r.' + QUOTENAME(@code) + N')) IN (SELECT ons_code FROM clean.ref_district);';

EXEC sp_executesql @sql;


SELECT ons_name, COUNT(*) AS years, MIN(ratio_year) AS first_year, MAX(ratio_year) AS last_year,
       SUM(CASE WHEN price_earnings_ratio IS NULL THEN 1 ELSE 0 END) AS missing_values
FROM clean.ratio GROUP BY ons_name ORDER BY ons_name;
