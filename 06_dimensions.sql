
USE ne_housing;
GO

DROP TABLE IF EXISTS dw.agg_district_rolling12;
DROP TABLE IF EXISTS dw.agg_district_month;
DROP TABLE IF EXISTS dw.fact_affordability;
DROP TABLE IF EXISTS dw.fact_sales;
DROP TABLE IF EXISTS dw.dim_date;
DROP TABLE IF EXISTS dw.dim_property_type;
DROP TABLE IF EXISTS dw.dim_tenure;
DROP TABLE IF EXISTS dw.dim_location;
GO

CREATE TABLE dw.dim_date (
    date_key     INT         NOT NULL PRIMARY KEY,   
    full_date    DATE        NOT NULL UNIQUE,
    year_num     SMALLINT    NOT NULL,
    quarter_num  TINYINT     NOT NULL,
    year_quarter CHAR(7)     NOT NULL,               
    month_num    TINYINT     NOT NULL,
    month_name   VARCHAR(10) NOT NULL,
    month_short  CHAR(3)     NOT NULL,
    year_month   CHAR(7)     NOT NULL,             
    month_start  DATE        NOT NULL,
    day_of_month TINYINT     NOT NULL,
    day_name     VARCHAR(10) NOT NULL,
    is_weekend   BIT         NOT NULL
);

DECLARE @start DATE = '2015-01-01', @end DATE = '2027-12-31';
;WITH n AS (
    SELECT TOP (DATEDIFF(DAY, @start, @end) + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
), dts AS (
    SELECT DATEADD(DAY, i, @start) AS d FROM n
)
INSERT dw.dim_date (date_key, full_date, year_num, quarter_num, year_quarter, month_num, month_name,
                    month_short, year_month, month_start, day_of_month, day_name, is_weekend)
SELECT YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
       d,
       YEAR(d),
       DATEPART(QUARTER, d),
       CONCAT(YEAR(d), '-Q', DATEPART(QUARTER, d)),
       MONTH(d),
       DATENAME(MONTH, d),
       LEFT(DATENAME(MONTH, d), 3),
       CONVERT(CHAR(7), d, 126),
       DATEFROMPARTS(YEAR(d), MONTH(d), 1),
       DAY(d),
       DATENAME(WEEKDAY, d),
       CASE WHEN DATENAME(WEEKDAY, d) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
FROM dts;
GO

CREATE TABLE dw.dim_property_type (
    property_type_key  INT IDENTITY(1,1) PRIMARY KEY,
    property_type_code CHAR(1)     NOT NULL UNIQUE,
    type_name          VARCHAR(30) NOT NULL,
    type_group         VARCHAR(10) NOT NULL,   -- House / Flat
    sort_order         TINYINT     NOT NULL
);
INSERT dw.dim_property_type (property_type_code, type_name, type_group, sort_order) VALUES
('D','Detached','House',1),
('S','Semi-detached','House',2),
('T','Terraced','House',3),
('F','Flat/Maisonette','Flat',4);


CREATE TABLE dw.dim_tenure (
    tenure_key  INT IDENTITY(1,1) PRIMARY KEY,
    tenure_code CHAR(1)     NOT NULL UNIQUE,
    tenure_name VARCHAR(15) NOT NULL
);
INSERT dw.dim_tenure (tenure_code, tenure_name) VALUES
('F','Freehold'),('L','Leasehold'),('U','Unknown');

CREATE TABLE dw.dim_location (
    location_key  INT IDENTITY(1,1) PRIMARY KEY,
    ons_code      CHAR(9)     NOT NULL UNIQUE,
    district_name VARCHAR(60) NOT NULL,
    lr_district   VARCHAR(60) NOT NULL UNIQUE,
    sub_region    VARCHAR(30) NOT NULL,
    la_type       VARCHAR(20) NOT NULL,
    region        VARCHAR(20) NOT NULL DEFAULT 'North East'
);
INSERT dw.dim_location (ons_code, district_name, lr_district, sub_region, la_type)
SELECT ons_code, ons_name, lr_district, sub_region, la_type
FROM clean.ref_district
ORDER BY sub_region, ons_name;

SELECT * FROM dw.dim_location;
