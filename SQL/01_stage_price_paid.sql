
USE ne_housing;
GO

DROP TABLE IF EXISTS staging.pp_load;
CREATE TABLE staging.pp_load (
    transaction_id    VARCHAR(100),
    price             VARCHAR(50),
    date_of_transfer  VARCHAR(50),
    postcode          VARCHAR(50),
    property_type     VARCHAR(10),
    old_new           VARCHAR(10),
    duration          VARCHAR(10),
    paon              VARCHAR(200),
    saon              VARCHAR(200),
    street            VARCHAR(200),
    locality          VARCHAR(200),
    town_city         VARCHAR(200),
    district          VARCHAR(200),
    county            VARCHAR(200),
    ppd_category_type VARCHAR(10),
    record_status     VARCHAR(10)
);

DROP TABLE IF EXISTS staging.pp_raw;
CREATE TABLE staging.pp_raw (
    load_id           BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_file       VARCHAR(100) NOT NULL,
    transaction_id    VARCHAR(100),
    price             VARCHAR(50),
    date_of_transfer  VARCHAR(50),
    postcode          VARCHAR(50),
    property_type     VARCHAR(10),
    old_new           VARCHAR(10),
    duration          VARCHAR(10),
    paon              VARCHAR(200),
    saon              VARCHAR(200),
    street            VARCHAR(200),
    locality          VARCHAR(200),
    town_city         VARCHAR(200),
    district          VARCHAR(200),
    county            VARCHAR(200),
    ppd_category_type VARCHAR(10),
    record_status     VARCHAR(10)
);
GO


DECLARE @folder NVARCHAR(260) = N'C:\data\price_paid\';   
DECLARE @ne_only BIT = 1;   

DECLARE @files TABLE (file_name NVARCHAR(100));
INSERT @files VALUES
 (N'pp-2015-part1.csv'),(N'pp-2015-part2.csv'),
 (N'pp-2016-part1.csv'),(N'pp-2016-part2.csv'),
 (N'pp-2017-part1.csv'),(N'pp-2017-part2.csv'),
 (N'pp-2018.csv'),(N'pp-2019.csv'),(N'pp-2020.csv'),(N'pp-2021.csv'),
 (N'pp-2022.csv'),(N'pp-2023.csv'),(N'pp-2024.csv'),(N'pp-2025.csv'),(N'pp-2026.csv');

DECLARE @f NVARCHAR(100), @path NVARCHAR(400), @sql NVARCHAR(MAX), @exists INT, @n INT;
DECLARE @ok BIT, @i INT, @term NVARCHAR(10);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT file_name FROM @files;
OPEN c;
FETCH NEXT FROM c INTO @f;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @path = @folder + @f;
    EXEC master.dbo.xp_fileexist @path, @exists OUTPUT;

    IF @exists = 1
    BEGIN
       
        SET @ok = 0; SET @i = 1;
        WHILE @ok = 0 AND @i <= 2
        BEGIN
            SET @term = CASE @i WHEN 1 THEN N'0x0a' ELSE N'\n' END;
            BEGIN TRY
                TRUNCATE TABLE staging.pp_load;
                SET @sql = N'BULK INSERT staging.pp_load FROM ''' + @path + N'''
                             WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', ROWTERMINATOR = ''' + @term + N''',
                                   CODEPAGE = ''65001'', TABLOCK);';
                EXEC (@sql);
                SET @ok = 1;
            END TRY
            BEGIN CATCH
                PRINT CONCAT('   attempt ', @i, ' failed for ', @f, ': ', ERROR_MESSAGE());
            END CATCH
            SET @i += 1;
        END

        IF @ok = 0
        BEGIN
            PRINT CONCAT('FAILED to load ', @f, ' - see messages above');
            FETCH NEXT FROM c INTO @f;
            CONTINUE;
        END

        INSERT staging.pp_raw (source_file, transaction_id, price, date_of_transfer, postcode,
               property_type, old_new, duration, paon, saon, street, locality, town_city,
               district, county, ppd_category_type, record_status)
        SELECT @f, transaction_id, price, date_of_transfer, postcode,
               property_type, old_new, duration, paon, saon, street, locality, town_city,
               district, county, ppd_category_type, record_status
        FROM staging.pp_load
        WHERE @ne_only = 0
           OR UPPER(LTRIM(RTRIM(district))) IN (SELECT lr_district FROM clean.ref_district);

        SET @n = @@ROWCOUNT;
        PRINT CONCAT('Loaded ', @f, ' -> ', @n, ' rows kept');
    END
    ELSE PRINT CONCAT('NOT FOUND (skipped): ', @path);

    FETCH NEXT FROM c INTO @f;
END
CLOSE c; DEALLOCATE c;

DROP TABLE IF EXISTS staging.pp_load;
GO

SELECT source_file, COUNT(*) AS row_count FROM staging.pp_raw GROUP BY source_file ORDER BY source_file;
SELECT UPPER(district) AS district, COUNT(*) AS row_count FROM staging.pp_raw GROUP BY UPPER(district) ORDER BY 1;
