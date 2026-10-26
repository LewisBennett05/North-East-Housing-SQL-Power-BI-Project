
USE ne_housing;
GO
DROP TABLE IF EXISTS dw.fact_affordability;
DROP TABLE IF EXISTS dw.fact_sales;

CREATE TABLE dw.fact_sales (
    sale_key          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    transaction_id    VARCHAR(36)  NOT NULL UNIQUE,
    date_key          INT          NOT NULL REFERENCES dw.dim_date(date_key),
    location_key      INT          NOT NULL REFERENCES dw.dim_location(location_key),
    property_type_key INT          NOT NULL REFERENCES dw.dim_property_type(property_type_key),
    tenure_key        INT          NOT NULL REFERENCES dw.dim_tenure(tenure_key),
    price             INT          NOT NULL,
    is_new_build      BIT          NULL,
    build_status      VARCHAR(10)  NULL,          
    postcode          VARCHAR(8)   NULL,         
    postcode_district VARCHAR(4)   NULL,         
    epc_matched       BIT          NOT NULL DEFAULT 0,
    epc_match_tier    TINYINT      NULL,
    floor_area_m2     DECIMAL(8,2) NULL,
    energy_rating     CHAR(1)      NULL,
    price_per_sqm     DECIMAL(10,2) NULL
);

INSERT dw.fact_sales (transaction_id, date_key, location_key, property_type_key, tenure_key, price,
                      is_new_build, build_status, postcode, postcode_district,
                      epc_matched, epc_match_tier, floor_area_m2, energy_rating, price_per_sqm)
SELECT s.transaction_id,
       dd.date_key,
       l.location_key,
       pt.property_type_key,
       t.tenure_key,
       s.price,
       s.is_new_build,
       CASE s.is_new_build WHEN 1 THEN 'New build' WHEN 0 THEN 'Existing' END,
       s.postcode,
       CASE WHEN s.postcode IS NOT NULL THEN LEFT(s.postcode, CHARINDEX(' ', s.postcode) - 1) END,
       CASE WHEN m.transaction_id IS NOT NULL THEN 1 ELSE 0 END,
       m.match_tier,
       m.floor_area_m2,
       m.energy_rating,
       
       CASE WHEN m.floor_area_m2 > 0
             AND s.price / m.floor_area_m2 BETWEEN 100 AND 10000
            THEN CAST(s.price / m.floor_area_m2 AS DECIMAL(10,2)) END
FROM clean.sales s
JOIN dw.dim_date          dd ON dd.full_date          = s.sale_date
JOIN dw.dim_location      l  ON l.lr_district         = s.district
JOIN dw.dim_property_type pt ON pt.property_type_code = s.property_type_code
JOIN dw.dim_tenure        t  ON t.tenure_code         = CASE WHEN s.tenure_code IN ('F','L') THEN s.tenure_code ELSE 'U' END
LEFT JOIN clean.sale_epc_match m ON m.transaction_id  = s.transaction_id;

CREATE INDEX ix_fs_date     ON dw.fact_sales (date_key)         INCLUDE (price);
CREATE INDEX ix_fs_location ON dw.fact_sales (location_key)     INCLUDE (price, date_key);
CREATE INDEX ix_fs_type     ON dw.fact_sales (property_type_key);


CREATE TABLE dw.fact_affordability (
    location_key         INT          NOT NULL REFERENCES dw.dim_location(location_key),
    ratio_year           INT          NOT NULL,
    date_key             INT          NOT NULL REFERENCES dw.dim_date(date_key),
    price_earnings_ratio DECIMAL(9,3) NOT NULL,
    source_label         VARCHAR(100) NULL,
    CONSTRAINT pk_fact_aff PRIMARY KEY (location_key, ratio_year)
);

INSERT dw.fact_affordability (location_key, ratio_year, date_key, price_earnings_ratio, source_label)
SELECT l.location_key, r.ratio_year, r.ratio_year * 10000 + 101, r.price_earnings_ratio, r.year_label
FROM clean.ratio r
JOIN dw.dim_location l ON l.ons_code = r.ons_code
WHERE r.ratio_year >= 2015 AND r.price_earnings_ratio IS NOT NULL;

SELECT (SELECT COUNT(*) FROM dw.fact_sales)         AS fact_sales_rows,
       (SELECT COUNT(*) FROM dw.fact_affordability) AS fact_affordability_rows;
