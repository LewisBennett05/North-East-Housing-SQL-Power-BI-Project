
USE ne_housing;
GO
DROP TABLE IF EXISTS clean.sale_epc_candidates;

SELECT x.transaction_id, x.tier, x.lmk_key, x.lodgement_date, x.sale_date,
       x.floor_area_m2, x.energy_rating
INTO clean.sale_epc_candidates
FROM (
    SELECT s.transaction_id, 1 AS tier, e.lmk_key, e.lodgement_date, s.sale_date, e.floor_area_m2, e.energy_rating
    FROM clean.sales s
    JOIN clean.epc e ON e.postcode_nospace = s.postcode_nospace AND e.addr_key1 = s.addr_full
    WHERE s.postcode_nospace IS NOT NULL

    UNION ALL
    SELECT s.transaction_id, 2, e.lmk_key, e.lodgement_date, s.sale_date, e.floor_area_m2, e.energy_rating
    FROM clean.sales s
    JOIN clean.epc e ON e.postcode_nospace = s.postcode_nospace AND e.addr_key12 = s.addr_full
    WHERE s.postcode_nospace IS NOT NULL

    UNION ALL
    SELECT s.transaction_id, 3, e.lmk_key, e.lodgement_date, s.sale_date, e.floor_area_m2, e.energy_rating
    FROM clean.sales s
    JOIN clean.epc e ON e.postcode_nospace = s.postcode_nospace AND e.addr_key1 = s.paon
    WHERE s.postcode_nospace IS NOT NULL
      AND s.saon IS NULL
      AND s.paon NOT LIKE '[0-9]%'
) x;

DROP TABLE IF EXISTS clean.sale_epc_match;

;WITH ranked AS (
    SELECT c.*,
           ROW_NUMBER() OVER (
               PARTITION BY c.transaction_id
               ORDER BY c.tier,
                        CASE WHEN c.lodgement_date <= c.sale_date THEN 0 ELSE 1 END,
                        ABS(DATEDIFF(DAY, c.lodgement_date, c.sale_date)),
                        c.lmk_key) AS rn
    FROM clean.sale_epc_candidates c
)
SELECT transaction_id, lmk_key, tier AS match_tier, floor_area_m2, energy_rating,
       DATEDIFF(DAY, lodgement_date, sale_date) AS days_cert_before_sale   
INTO clean.sale_epc_match
FROM ranked
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX cx_sale_epc_match ON clean.sale_epc_match (transaction_id);


SELECT COUNT(*)                                                      AS valid_sales,
       (SELECT COUNT(*) FROM clean.sale_epc_match)                   AS matched,
       CAST(100.0 * (SELECT COUNT(*) FROM clean.sale_epc_match) / COUNT(*) AS DECIMAL(5,1)) AS match_pct
FROM clean.sales;

SELECT match_tier, COUNT(*) AS matches FROM clean.sale_epc_match GROUP BY match_tier ORDER BY match_tier;
