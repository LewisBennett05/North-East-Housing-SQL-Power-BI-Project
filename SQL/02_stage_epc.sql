
USE ne_housing;
GO
DROP TABLE IF EXISTS staging.epc_raw;
CREATE TABLE staging.epc_raw (
    source_file               VARCHAR(100),
    lmk_key                   VARCHAR(1000),
    address1                  VARCHAR(1000),
    address2                  VARCHAR(1000),
    address3                  VARCHAR(1000),
    postcode                  VARCHAR(1000),
    uprn                      VARCHAR(1000),
    lodgement_date            VARCHAR(1000),
    inspection_date           VARCHAR(1000),
    total_floor_area          VARCHAR(1000),
    current_energy_rating     VARCHAR(1000),
    current_energy_efficiency VARCHAR(1000),
    property_type             VARCHAR(1000),
    built_form                VARCHAR(1000),
    construction_age_band     VARCHAR(1000),
    tenure                    VARCHAR(1000),
    number_habitable_rooms    VARCHAR(1000),
    local_authority           VARCHAR(1000)
);
SELECT COUNT(*) AS epc_rows_placeholder FROM staging.epc_raw;   -- 0 is expected
