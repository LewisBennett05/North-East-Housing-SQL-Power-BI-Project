
USE ne_housing;
GO
SET NOCOUNT ON;

DECLARE @file NVARCHAR(500) = N'C:\Housingdata\ons_ratio_la.csv';      -- <<< EDIT ME

DECLARE @sql NVARCHAR(MAX), @ok BIT, @i INT, @term NVARCHAR(10), @ex INT;

EXEC master.dbo.xp_fileexist @file, @ex OUTPUT;
IF @ex <> 1
BEGIN
    RAISERROR('File not found: %s  (check the path, and that SQL Server can read that folder)', 16, 1, @file);
    RETURN;
END


DROP TABLE IF EXISTS #hdr;
CREATE TABLE #hdr (line VARCHAR(MAX));
SET @sql = N'BULK INSERT #hdr FROM ''' + @file + N'''
             WITH (FIRSTROW = 1, LASTROW = 1, ROWTERMINATOR = ''0x0a'', FIELDTERMINATOR = ''\t'', CODEPAGE = ''65001'');';
EXEC (@sql);

DECLARE @hdr  NVARCHAR(MAX) = (SELECT REPLACE(REPLACE(line, CHAR(13), ''), '"', '') FROM #hdr);
DECLARE @json NVARCHAR(MAX) = N'["' + REPLACE(@hdr, ',', '","') + N'"]';


DROP TABLE IF EXISTS #cols;
;WITH raw AS (
    SELECT CAST([key] AS INT) + 1 AS ord,
           CASE WHEN [key] = '0'
                THEN LTRIM(RTRIM(SUBSTRING(value, NULLIF(PATINDEX('%[A-Za-z0-9]%', value), 0), 200)))   
                ELSE LTRIM(RTRIM(value)) END AS nm
    FROM OPENJSON(@json)
), named AS (
    SELECT ord,
           CASE WHEN ISNULL(nm, '') = '' THEN CONCAT('col_', ord) ELSE nm END AS nm
    FROM raw
), dedup AS (
    SELECT ord, nm, ROW_NUMBER() OVER (PARTITION BY nm ORDER BY ord) AS rn FROM named
)
SELECT ord, CASE WHEN rn = 1 THEN nm ELSE CONCAT(nm, '_', rn) END AS col
INTO #cols
FROM dedup;

SELECT ord, col FROM #cols ORDER BY ord;    


DROP TABLE IF EXISTS staging.ratio_raw;
SELECT @sql = N'CREATE TABLE staging.ratio_raw (' +
       STRING_AGG(CAST(QUOTENAME(col) + N' VARCHAR(200) NULL' AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY ord) + N');'
FROM #cols;
EXEC (@sql);

SET @ok = 0; SET @i = 1;
WHILE @ok = 0 AND @i <= 2                     
BEGIN
    SET @term = CASE @i WHEN 1 THEN N'0x0a' ELSE N'\n' END;
    BEGIN TRY
        TRUNCATE TABLE staging.ratio_raw;
        SET @sql = N'BULK INSERT staging.ratio_raw FROM ''' + @file + N'''
                     WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2, ROWTERMINATOR = ''' + @term + N''',
                           CODEPAGE = ''65001'', TABLOCK);';
        EXEC (@sql);
        SET @ok = 1;
    END TRY
    BEGIN CATCH
        PRINT CONCAT('   attempt ', @i, ' failed: ', ERROR_MESSAGE());
    END CATCH
    SET @i += 1;
END
IF @ok = 0 RAISERROR('Could not load the ONS file - see the attempt messages above.', 16, 1);
GO


SELECT COUNT(*) AS rows_loaded FROM staging.ratio_raw;
SELECT TOP 20 * FROM staging.ratio_raw;
SELECT COLUMN_NAME, ORDINAL_POSITION FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'staging' AND TABLE_NAME = 'ratio_raw' ORDER BY ORDINAL_POSITION;
