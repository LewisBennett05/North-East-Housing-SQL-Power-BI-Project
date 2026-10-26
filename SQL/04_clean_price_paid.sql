
USE ne_housing;
GO

DECLARE @study_start DATE = '2015-01-01';
DECLARE @min_price   INT  = 10000;      
DECLARE @max_price   INT  = 5000000;    

DROP TABLE IF EXISTS clean.pp_typed;

;WITH ne AS (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY REPLACE(REPLACE(UPPER(LTRIM(RTRIM(r.transaction_id))), '{', ''), '}', '')
               ORDER BY r.load_id DESC) AS rn
    FROM staging.pp_raw r
    WHERE UPPER(LTRIM(RTRIM(r.district))) IN (SELECT lr_district FROM clean.ref_district)
)
SELECT
    CAST(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(transaction_id))), '{', ''), '}', '') AS VARCHAR(36)) AS transaction_id,
    TRY_CAST(price AS INT)                                  AS price,
    TRY_CAST(LEFT(date_of_transfer, 10) AS DATE)            AS sale_date,
    CAST(clean.fn_postcode_nospace(postcode) AS VARCHAR(20)) AS postcode_nospace,
    CAST(NULL AS VARCHAR(8))                                AS postcode,          
    UPPER(LTRIM(RTRIM(property_type)))                      AS property_type_code, 
    CASE UPPER(LTRIM(RTRIM(old_new))) WHEN 'Y' THEN 1 WHEN 'N' THEN 0 END AS is_new_build,
    UPPER(LTRIM(RTRIM(duration)))                           AS tenure_code,        
    clean.fn_norm_text(paon)                                AS paon,
    clean.fn_norm_text(saon)                                AS saon,
    clean.fn_norm_text(street)                              AS street,
    clean.fn_norm_text(CONCAT_WS(' ', clean.fn_norm_text(saon), clean.fn_norm_text(paon), clean.fn_norm_text(street))) AS addr_full,
    clean.fn_norm_text(locality)                            AS locality,
    clean.fn_norm_text(town_city)                           AS town_city,
    UPPER(LTRIM(RTRIM(district)))                           AS district,
    UPPER(LTRIM(RTRIM(county)))                             AS county,
    UPPER(LTRIM(RTRIM(ppd_category_type)))                  AS ppd_category_type,  
    UPPER(LTRIM(RTRIM(record_status)))                      AS record_status,
    source_file,
    CAST(NULL AS VARCHAR(60))                               AS reject_reason
INTO clean.pp_typed
FROM ne
WHERE rn = 1;

UPDATE clean.pp_typed
SET postcode_nospace = NULL
WHERE postcode_nospace IS NOT NULL
  AND NOT (LEN(postcode_nospace) BETWEEN 5 AND 7 AND postcode_nospace LIKE '%[0-9][A-Z][A-Z]');

UPDATE clean.pp_typed
SET postcode = STUFF(postcode_nospace, LEN(postcode_nospace) - 2, 0, ' ')
WHERE postcode_nospace IS NOT NULL;


UPDATE clean.pp_typed SET reject_reason = 'Deleted record (status D)'
WHERE reject_reason IS NULL AND record_status = 'D';

UPDATE clean.pp_typed SET reject_reason = 'Unparseable price or date'
WHERE reject_reason IS NULL AND (price IS NULL OR sale_date IS NULL);

UPDATE clean.pp_typed SET reject_reason = 'Before study period'
WHERE reject_reason IS NULL AND sale_date < @study_start;

UPDATE clean.pp_typed SET reject_reason = 'Non-standard sale (category B)'
WHERE reject_reason IS NULL AND ppd_category_type = 'B';

UPDATE clean.pp_typed SET reject_reason = 'Property type other/unknown'
WHERE reject_reason IS NULL AND property_type_code NOT IN ('D','S','T','F');

UPDATE clean.pp_typed SET reject_reason = 'Price below minimum'
WHERE reject_reason IS NULL AND price < @min_price;

UPDATE clean.pp_typed SET reject_reason = 'Price above maximum'
WHERE reject_reason IS NULL AND price > @max_price;

;WITH d AS (
    SELECT reject_reason,
           ROW_NUMBER() OVER (PARTITION BY postcode_nospace, paon, saon, street, sale_date, price
                              ORDER BY transaction_id) AS rn
    FROM clean.pp_typed
    WHERE reject_reason IS NULL AND postcode_nospace IS NOT NULL
)
UPDATE d SET reject_reason = 'Duplicate sale (same address/date/price)' WHERE rn > 1;

CREATE INDEX ix_pp_typed_postcode ON clean.pp_typed (postcode_nospace);
GO

CREATE OR ALTER VIEW clean.sales AS
SELECT * FROM clean.pp_typed WHERE reject_reason IS NULL;
GO


SELECT ISNULL(reject_reason, '== KEPT ==') AS outcome,
       COUNT(*) AS row_count,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct
FROM clean.pp_typed
GROUP BY reject_reason
ORDER BY row_count DESC;
