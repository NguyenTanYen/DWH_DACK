/* =====================================================================
   F1_SOURCE – CƠ SỞ DỮ LIỆU NGUỒN (OLTP) CHO ĐỒ ÁN KHO DỮ LIỆU
   Đưa nguyên 14 file CSV (Formula 1, 1950–2024) vào SQL Server,
   giữ đúng cấu trúc gốc + khoá chính + khoá ngoại.

   Cách chạy: mở file trong SSMS  ->  sửa @DataPath (ở BƯỚC 1) nếu cần
              ->  bấm Execute (F5). Chạy lại nhiều lần được (xoá & tạo lại).
   Yêu cầu : SQL Server 2017 trở lên (BULK INSERT ... FORMAT = 'CSV').

   Các bước:
     0. Tạo database F1_SOURCE
     1. Tạo bảng tạm stg.* (toàn cột chữ) và BULK INSERT từ CSV
     2. Tạo bảng dbo.* đúng kiểu dữ liệu + khoá chính
     3. Chuyển stg -> dbo: '\N' thành NULL, ép kiểu
     4. Tạo khoá ngoại
     5. Kiểm tra số dòng
   ===================================================================== */
USE master;
GO
IF DB_ID('F1_SOURCE') IS NOT NULL
BEGIN
    ALTER DATABASE F1_SOURCE SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE F1_SOURCE;
END
GO
CREATE DATABASE F1_SOURCE;
GO
USE F1_SOURCE;
GO
CREATE SCHEMA stg;
GO

/* =========================== BƯỚC 1: NẠP CSV THÔ =========================== */
CREATE TABLE stg.seasons (
    [year] NVARCHAR(255) NULL,
    [url] NVARCHAR(255) NULL
);
CREATE TABLE stg.circuits (
    [circuitId] NVARCHAR(255) NULL,
    [circuitRef] NVARCHAR(255) NULL,
    [name] NVARCHAR(255) NULL,
    [location] NVARCHAR(255) NULL,
    [country] NVARCHAR(255) NULL,
    [lat] NVARCHAR(255) NULL,
    [lng] NVARCHAR(255) NULL,
    [alt] NVARCHAR(255) NULL,
    [url] NVARCHAR(255) NULL
);
CREATE TABLE stg.constructors (
    [constructorId] NVARCHAR(255) NULL,
    [constructorRef] NVARCHAR(255) NULL,
    [name] NVARCHAR(255) NULL,
    [nationality] NVARCHAR(255) NULL,
    [url] NVARCHAR(255) NULL
);
CREATE TABLE stg.drivers (
    [driverId] NVARCHAR(255) NULL,
    [driverRef] NVARCHAR(255) NULL,
    [number] NVARCHAR(255) NULL,
    [code] NVARCHAR(255) NULL,
    [forename] NVARCHAR(255) NULL,
    [surname] NVARCHAR(255) NULL,
    [dob] NVARCHAR(255) NULL,
    [nationality] NVARCHAR(255) NULL,
    [url] NVARCHAR(255) NULL
);
CREATE TABLE stg.status (
    [statusId] NVARCHAR(255) NULL,
    [status] NVARCHAR(255) NULL
);
CREATE TABLE stg.races (
    [raceId] NVARCHAR(255) NULL,
    [year] NVARCHAR(255) NULL,
    [round] NVARCHAR(255) NULL,
    [circuitId] NVARCHAR(255) NULL,
    [name] NVARCHAR(255) NULL,
    [date] NVARCHAR(255) NULL,
    [time] NVARCHAR(255) NULL,
    [url] NVARCHAR(255) NULL,
    [fp1_date] NVARCHAR(255) NULL,
    [fp1_time] NVARCHAR(255) NULL,
    [fp2_date] NVARCHAR(255) NULL,
    [fp2_time] NVARCHAR(255) NULL,
    [fp3_date] NVARCHAR(255) NULL,
    [fp3_time] NVARCHAR(255) NULL,
    [quali_date] NVARCHAR(255) NULL,
    [quali_time] NVARCHAR(255) NULL,
    [sprint_date] NVARCHAR(255) NULL,
    [sprint_time] NVARCHAR(255) NULL
);
CREATE TABLE stg.results (
    [resultId] NVARCHAR(255) NULL,
    [raceId] NVARCHAR(255) NULL,
    [driverId] NVARCHAR(255) NULL,
    [constructorId] NVARCHAR(255) NULL,
    [number] NVARCHAR(255) NULL,
    [grid] NVARCHAR(255) NULL,
    [position] NVARCHAR(255) NULL,
    [positionText] NVARCHAR(255) NULL,
    [positionOrder] NVARCHAR(255) NULL,
    [points] NVARCHAR(255) NULL,
    [laps] NVARCHAR(255) NULL,
    [time] NVARCHAR(255) NULL,
    [milliseconds] NVARCHAR(255) NULL,
    [fastestLap] NVARCHAR(255) NULL,
    [rank] NVARCHAR(255) NULL,
    [fastestLapTime] NVARCHAR(255) NULL,
    [fastestLapSpeed] NVARCHAR(255) NULL,
    [statusId] NVARCHAR(255) NULL
);
CREATE TABLE stg.sprint_results (
    [resultId] NVARCHAR(255) NULL,
    [raceId] NVARCHAR(255) NULL,
    [driverId] NVARCHAR(255) NULL,
    [constructorId] NVARCHAR(255) NULL,
    [number] NVARCHAR(255) NULL,
    [grid] NVARCHAR(255) NULL,
    [position] NVARCHAR(255) NULL,
    [positionText] NVARCHAR(255) NULL,
    [positionOrder] NVARCHAR(255) NULL,
    [points] NVARCHAR(255) NULL,
    [laps] NVARCHAR(255) NULL,
    [time] NVARCHAR(255) NULL,
    [milliseconds] NVARCHAR(255) NULL,
    [fastestLap] NVARCHAR(255) NULL,
    [fastestLapTime] NVARCHAR(255) NULL,
    [statusId] NVARCHAR(255) NULL
);
CREATE TABLE stg.qualifying (
    [qualifyId] NVARCHAR(255) NULL,
    [raceId] NVARCHAR(255) NULL,
    [driverId] NVARCHAR(255) NULL,
    [constructorId] NVARCHAR(255) NULL,
    [number] NVARCHAR(255) NULL,
    [position] NVARCHAR(255) NULL,
    [q1] NVARCHAR(255) NULL,
    [q2] NVARCHAR(255) NULL,
    [q3] NVARCHAR(255) NULL
);
CREATE TABLE stg.lap_times (
    [raceId] NVARCHAR(255) NULL,
    [driverId] NVARCHAR(255) NULL,
    [lap] NVARCHAR(255) NULL,
    [position] NVARCHAR(255) NULL,
    [time] NVARCHAR(255) NULL,
    [milliseconds] NVARCHAR(255) NULL
);
CREATE TABLE stg.pit_stops (
    [raceId] NVARCHAR(255) NULL,
    [driverId] NVARCHAR(255) NULL,
    [stop] NVARCHAR(255) NULL,
    [lap] NVARCHAR(255) NULL,
    [time] NVARCHAR(255) NULL,
    [duration] NVARCHAR(255) NULL,
    [milliseconds] NVARCHAR(255) NULL
);
CREATE TABLE stg.driver_standings (
    [driverStandingsId] NVARCHAR(255) NULL,
    [raceId] NVARCHAR(255) NULL,
    [driverId] NVARCHAR(255) NULL,
    [points] NVARCHAR(255) NULL,
    [position] NVARCHAR(255) NULL,
    [positionText] NVARCHAR(255) NULL,
    [wins] NVARCHAR(255) NULL
);
CREATE TABLE stg.constructor_standings (
    [constructorStandingsId] NVARCHAR(255) NULL,
    [raceId] NVARCHAR(255) NULL,
    [constructorId] NVARCHAR(255) NULL,
    [points] NVARCHAR(255) NULL,
    [position] NVARCHAR(255) NULL,
    [positionText] NVARCHAR(255) NULL,
    [wins] NVARCHAR(255) NULL
);
CREATE TABLE stg.constructor_results (
    [constructorResultsId] NVARCHAR(255) NULL,
    [raceId] NVARCHAR(255) NULL,
    [constructorId] NVARCHAR(255) NULL,
    [points] NVARCHAR(255) NULL,
    [status] NVARCHAR(255) NULL
);
GO

-- >>> SỬA ĐƯỜNG DẪN NÀY nếu bạn để CSV ở chỗ khác (nhớ dấu \ ở cuối) <<<
DECLARE @DataPath NVARCHAR(400) = N'D:\1. DWH\DACK\DATASET\archive\';
DECLARE @sql NVARCHAR(MAX) = N'';
DECLARE @t SYSNAME;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM (VALUES ('seasons'), ('circuits'), ('constructors'), ('drivers'), ('status'), ('races'), ('results'), ('sprint_results'), ('qualifying'), ('lap_times'), ('pit_stops'), ('driver_standings'), ('constructor_standings'), ('constructor_results')) v(name);
OPEN cur;
FETCH NEXT FROM cur INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'BULK INSERT stg.' + QUOTENAME(@t) + N' FROM ''' + @DataPath + @t + N'.csv''
        WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'',
              FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'',
              CODEPAGE = ''65001'', TABLOCK);';
    EXEC sp_executesql @sql;
    PRINT N'Đã nạp ' + @t;
    FETCH NEXT FROM cur INTO @t;
END
CLOSE cur; DEALLOCATE cur;
GO

/* ================== BƯỚC 2: BẢNG CHÍNH THỨC (ĐÚNG KIỂU + KHOÁ CHÍNH) ================== */
CREATE TABLE dbo.seasons (
    [year] INT NOT NULL,
    [url] NVARCHAR(255) NULL,
    CONSTRAINT PK_seasons PRIMARY KEY ([year])
);
CREATE TABLE dbo.circuits (
    [circuitId] INT NOT NULL,
    [circuitRef] NVARCHAR(50) NULL,
    [name] NVARCHAR(100) NULL,
    [location] NVARCHAR(100) NULL,
    [country] NVARCHAR(50) NULL,
    [lat] DECIMAL(9,5) NULL,
    [lng] DECIMAL(9,5) NULL,
    [alt] INT NULL,
    [url] NVARCHAR(255) NULL,
    CONSTRAINT PK_circuits PRIMARY KEY ([circuitId])
);
CREATE TABLE dbo.constructors (
    [constructorId] INT NOT NULL,
    [constructorRef] NVARCHAR(50) NULL,
    [name] NVARCHAR(100) NULL,
    [nationality] NVARCHAR(50) NULL,
    [url] NVARCHAR(255) NULL,
    CONSTRAINT PK_constructors PRIMARY KEY ([constructorId])
);
CREATE TABLE dbo.drivers (
    [driverId] INT NOT NULL,
    [driverRef] NVARCHAR(50) NULL,
    [number] INT NULL,
    [code] NVARCHAR(3) NULL,
    [forename] NVARCHAR(50) NULL,
    [surname] NVARCHAR(50) NULL,
    [dob] DATE NULL,
    [nationality] NVARCHAR(50) NULL,
    [url] NVARCHAR(255) NULL,
    CONSTRAINT PK_drivers PRIMARY KEY ([driverId])
);
CREATE TABLE dbo.status (
    [statusId] INT NOT NULL,
    [status] NVARCHAR(50) NULL,
    CONSTRAINT PK_status PRIMARY KEY ([statusId])
);
CREATE TABLE dbo.races (
    [raceId] INT NOT NULL,
    [year] INT NULL,
    [round] INT NULL,
    [circuitId] INT NULL,
    [name] NVARCHAR(100) NULL,
    [date] DATE NULL,
    [time] TIME(0) NULL,
    [url] NVARCHAR(255) NULL,
    [fp1_date] DATE NULL,
    [fp1_time] TIME(0) NULL,
    [fp2_date] DATE NULL,
    [fp2_time] TIME(0) NULL,
    [fp3_date] DATE NULL,
    [fp3_time] TIME(0) NULL,
    [quali_date] DATE NULL,
    [quali_time] TIME(0) NULL,
    [sprint_date] DATE NULL,
    [sprint_time] TIME(0) NULL,
    CONSTRAINT PK_races PRIMARY KEY ([raceId])
);
CREATE TABLE dbo.results (
    [resultId] INT NOT NULL,
    [raceId] INT NULL,
    [driverId] INT NULL,
    [constructorId] INT NULL,
    [number] INT NULL,
    [grid] INT NULL,
    [position] INT NULL,
    [positionText] NVARCHAR(5) NULL,
    [positionOrder] INT NULL,
    [points] DECIMAL(6,2) NULL,
    [laps] INT NULL,
    [time] NVARCHAR(20) NULL,
    [milliseconds] INT NULL,
    [fastestLap] INT NULL,
    [rank] INT NULL,
    [fastestLapTime] NVARCHAR(20) NULL,
    [fastestLapSpeed] DECIMAL(7,3) NULL,
    [statusId] INT NULL,
    CONSTRAINT PK_results PRIMARY KEY ([resultId])
);
CREATE TABLE dbo.sprint_results (
    [resultId] INT NOT NULL,
    [raceId] INT NULL,
    [driverId] INT NULL,
    [constructorId] INT NULL,
    [number] INT NULL,
    [grid] INT NULL,
    [position] INT NULL,
    [positionText] NVARCHAR(5) NULL,
    [positionOrder] INT NULL,
    [points] DECIMAL(6,2) NULL,
    [laps] INT NULL,
    [time] NVARCHAR(20) NULL,
    [milliseconds] INT NULL,
    [fastestLap] INT NULL,
    [fastestLapTime] NVARCHAR(20) NULL,
    [statusId] INT NULL,
    CONSTRAINT PK_sprint_results PRIMARY KEY ([resultId])
);
CREATE TABLE dbo.qualifying (
    [qualifyId] INT NOT NULL,
    [raceId] INT NULL,
    [driverId] INT NULL,
    [constructorId] INT NULL,
    [number] INT NULL,
    [position] INT NULL,
    [q1] NVARCHAR(20) NULL,
    [q2] NVARCHAR(20) NULL,
    [q3] NVARCHAR(20) NULL,
    CONSTRAINT PK_qualifying PRIMARY KEY ([qualifyId])
);
CREATE TABLE dbo.lap_times (
    [raceId] INT NOT NULL,
    [driverId] INT NOT NULL,
    [lap] INT NOT NULL,
    [position] INT NULL,
    [time] NVARCHAR(20) NULL,
    [milliseconds] INT NULL,
    CONSTRAINT PK_lap_times PRIMARY KEY ([raceId], [driverId], [lap])
);
CREATE TABLE dbo.pit_stops (
    [raceId] INT NOT NULL,
    [driverId] INT NOT NULL,
    [stop] INT NOT NULL,
    [lap] INT NULL,
    [time] TIME(0) NULL,
    [duration] NVARCHAR(20) NULL,
    [milliseconds] INT NULL,
    CONSTRAINT PK_pit_stops PRIMARY KEY ([raceId], [driverId], [stop])
);
CREATE TABLE dbo.driver_standings (
    [driverStandingsId] INT NOT NULL,
    [raceId] INT NULL,
    [driverId] INT NULL,
    [points] DECIMAL(6,2) NULL,
    [position] INT NULL,
    [positionText] NVARCHAR(5) NULL,
    [wins] INT NULL,
    CONSTRAINT PK_driver_standings PRIMARY KEY ([driverStandingsId])
);
CREATE TABLE dbo.constructor_standings (
    [constructorStandingsId] INT NOT NULL,
    [raceId] INT NULL,
    [constructorId] INT NULL,
    [points] DECIMAL(6,2) NULL,
    [position] INT NULL,
    [positionText] NVARCHAR(5) NULL,
    [wins] INT NULL,
    CONSTRAINT PK_constructor_standings PRIMARY KEY ([constructorStandingsId])
);
CREATE TABLE dbo.constructor_results (
    [constructorResultsId] INT NOT NULL,
    [raceId] INT NULL,
    [constructorId] INT NULL,
    [points] DECIMAL(6,2) NULL,
    [status] NVARCHAR(5) NULL,
    CONSTRAINT PK_constructor_results PRIMARY KEY ([constructorResultsId])
);
GO

/* ================== BƯỚC 3: CHUYỂN stg -> dbo ('\N' -> NULL, ép kiểu) ================== */
INSERT INTO dbo.seasons ([year], [url])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([year])), N'\N')),
       NULLIF(LTRIM(RTRIM([url])), N'\N')
FROM stg.seasons;
INSERT INTO dbo.circuits ([circuitId], [circuitRef], [name], [location], [country], [lat], [lng], [alt], [url])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([circuitId])), N'\N')),
       NULLIF(LTRIM(RTRIM([circuitRef])), N'\N'),
       NULLIF(LTRIM(RTRIM([name])), N'\N'),
       NULLIF(LTRIM(RTRIM([location])), N'\N'),
       NULLIF(LTRIM(RTRIM([country])), N'\N'),
       TRY_CONVERT(DECIMAL(9,5), NULLIF(LTRIM(RTRIM([lat])), N'\N')),
       TRY_CONVERT(DECIMAL(9,5), NULLIF(LTRIM(RTRIM([lng])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([alt])), N'\N')),
       NULLIF(LTRIM(RTRIM([url])), N'\N')
FROM stg.circuits;
INSERT INTO dbo.constructors ([constructorId], [constructorRef], [name], [nationality], [url])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorId])), N'\N')),
       NULLIF(LTRIM(RTRIM([constructorRef])), N'\N'),
       NULLIF(LTRIM(RTRIM([name])), N'\N'),
       NULLIF(LTRIM(RTRIM([nationality])), N'\N'),
       NULLIF(LTRIM(RTRIM([url])), N'\N')
FROM stg.constructors;
INSERT INTO dbo.drivers ([driverId], [driverRef], [number], [code], [forename], [surname], [dob], [nationality], [url])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverId])), N'\N')),
       NULLIF(LTRIM(RTRIM([driverRef])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([number])), N'\N')),
       NULLIF(LTRIM(RTRIM([code])), N'\N'),
       NULLIF(LTRIM(RTRIM([forename])), N'\N'),
       NULLIF(LTRIM(RTRIM([surname])), N'\N'),
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM([dob])), N'\N')),
       NULLIF(LTRIM(RTRIM([nationality])), N'\N'),
       NULLIF(LTRIM(RTRIM([url])), N'\N')
FROM stg.drivers;
INSERT INTO dbo.status ([statusId], [status])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([statusId])), N'\N')),
       NULLIF(LTRIM(RTRIM([status])), N'\N')
FROM stg.status;
INSERT INTO dbo.races ([raceId], [year], [round], [circuitId], [name], [date], [time], [url], [fp1_date], [fp1_time], [fp2_date], [fp2_time], [fp3_date], [fp3_time], [quali_date], [quali_time], [sprint_date], [sprint_time])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([year])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([round])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([circuitId])), N'\N')),
       NULLIF(LTRIM(RTRIM([name])), N'\N'),
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM([date])), N'\N')),
       TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM([time])), N'\N')),
       NULLIF(LTRIM(RTRIM([url])), N'\N'),
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM([fp1_date])), N'\N')),
       TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM([fp1_time])), N'\N')),
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM([fp2_date])), N'\N')),
       TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM([fp2_time])), N'\N')),
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM([fp3_date])), N'\N')),
       TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM([fp3_time])), N'\N')),
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM([quali_date])), N'\N')),
       TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM([quali_time])), N'\N')),
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM([sprint_date])), N'\N')),
       TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM([sprint_time])), N'\N'))
FROM stg.races;
INSERT INTO dbo.results ([resultId], [raceId], [driverId], [constructorId], [number], [grid], [position], [positionText], [positionOrder], [points], [laps], [time], [milliseconds], [fastestLap], [rank], [fastestLapTime], [fastestLapSpeed], [statusId])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([resultId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([number])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([grid])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([position])), N'\N')),
       NULLIF(LTRIM(RTRIM([positionText])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([positionOrder])), N'\N')),
       TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM([points])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([laps])), N'\N')),
       NULLIF(LTRIM(RTRIM([time])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([milliseconds])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([fastestLap])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([rank])), N'\N')),
       NULLIF(LTRIM(RTRIM([fastestLapTime])), N'\N'),
       TRY_CONVERT(DECIMAL(7,3), NULLIF(LTRIM(RTRIM([fastestLapSpeed])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([statusId])), N'\N'))
FROM stg.results;
INSERT INTO dbo.sprint_results ([resultId], [raceId], [driverId], [constructorId], [number], [grid], [position], [positionText], [positionOrder], [points], [laps], [time], [milliseconds], [fastestLap], [fastestLapTime], [statusId])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([resultId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([number])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([grid])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([position])), N'\N')),
       NULLIF(LTRIM(RTRIM([positionText])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([positionOrder])), N'\N')),
       TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM([points])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([laps])), N'\N')),
       NULLIF(LTRIM(RTRIM([time])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([milliseconds])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([fastestLap])), N'\N')),
       NULLIF(LTRIM(RTRIM([fastestLapTime])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([statusId])), N'\N'))
FROM stg.sprint_results;
INSERT INTO dbo.qualifying ([qualifyId], [raceId], [driverId], [constructorId], [number], [position], [q1], [q2], [q3])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([qualifyId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([number])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([position])), N'\N')),
       NULLIF(LTRIM(RTRIM([q1])), N'\N'),
       NULLIF(LTRIM(RTRIM([q2])), N'\N'),
       NULLIF(LTRIM(RTRIM([q3])), N'\N')
FROM stg.qualifying;
INSERT INTO dbo.lap_times ([raceId], [driverId], [lap], [position], [time], [milliseconds])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([lap])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([position])), N'\N')),
       NULLIF(LTRIM(RTRIM([time])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([milliseconds])), N'\N'))
FROM stg.lap_times;
INSERT INTO dbo.pit_stops ([raceId], [driverId], [stop], [lap], [time], [duration], [milliseconds])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([stop])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([lap])), N'\N')),
       TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM([time])), N'\N')),
       NULLIF(LTRIM(RTRIM([duration])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([milliseconds])), N'\N'))
FROM stg.pit_stops;
INSERT INTO dbo.driver_standings ([driverStandingsId], [raceId], [driverId], [points], [position], [positionText], [wins])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverStandingsId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([driverId])), N'\N')),
       TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM([points])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([position])), N'\N')),
       NULLIF(LTRIM(RTRIM([positionText])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([wins])), N'\N'))
FROM stg.driver_standings;
INSERT INTO dbo.constructor_standings ([constructorStandingsId], [raceId], [constructorId], [points], [position], [positionText], [wins])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorStandingsId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorId])), N'\N')),
       TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM([points])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([position])), N'\N')),
       NULLIF(LTRIM(RTRIM([positionText])), N'\N'),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([wins])), N'\N'))
FROM stg.constructor_standings;
INSERT INTO dbo.constructor_results ([constructorResultsId], [raceId], [constructorId], [points], [status])
SELECT TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorResultsId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([raceId])), N'\N')),
       TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM([constructorId])), N'\N')),
       TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM([points])), N'\N')),
       NULLIF(LTRIM(RTRIM([status])), N'\N')
FROM stg.constructor_results;
GO

/* =========================== BƯỚC 4: KHOÁ NGOẠI =========================== */
ALTER TABLE dbo.races ADD CONSTRAINT FK_races_seasons_year FOREIGN KEY ([year]) REFERENCES dbo.seasons ([year]);
ALTER TABLE dbo.races ADD CONSTRAINT FK_races_circuits_circuitId FOREIGN KEY ([circuitId]) REFERENCES dbo.circuits ([circuitId]);
ALTER TABLE dbo.results ADD CONSTRAINT FK_results_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.results ADD CONSTRAINT FK_results_drivers_driverId FOREIGN KEY ([driverId]) REFERENCES dbo.drivers ([driverId]);
ALTER TABLE dbo.results ADD CONSTRAINT FK_results_constructors_constructorId FOREIGN KEY ([constructorId]) REFERENCES dbo.constructors ([constructorId]);
ALTER TABLE dbo.results ADD CONSTRAINT FK_results_status_statusId FOREIGN KEY ([statusId]) REFERENCES dbo.status ([statusId]);
ALTER TABLE dbo.sprint_results ADD CONSTRAINT FK_sprint_results_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.sprint_results ADD CONSTRAINT FK_sprint_results_drivers_driverId FOREIGN KEY ([driverId]) REFERENCES dbo.drivers ([driverId]);
ALTER TABLE dbo.sprint_results ADD CONSTRAINT FK_sprint_results_constructors_constructorId FOREIGN KEY ([constructorId]) REFERENCES dbo.constructors ([constructorId]);
ALTER TABLE dbo.sprint_results ADD CONSTRAINT FK_sprint_results_status_statusId FOREIGN KEY ([statusId]) REFERENCES dbo.status ([statusId]);
ALTER TABLE dbo.qualifying ADD CONSTRAINT FK_qualifying_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.qualifying ADD CONSTRAINT FK_qualifying_drivers_driverId FOREIGN KEY ([driverId]) REFERENCES dbo.drivers ([driverId]);
ALTER TABLE dbo.qualifying ADD CONSTRAINT FK_qualifying_constructors_constructorId FOREIGN KEY ([constructorId]) REFERENCES dbo.constructors ([constructorId]);
ALTER TABLE dbo.lap_times ADD CONSTRAINT FK_lap_times_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.lap_times ADD CONSTRAINT FK_lap_times_drivers_driverId FOREIGN KEY ([driverId]) REFERENCES dbo.drivers ([driverId]);
ALTER TABLE dbo.pit_stops ADD CONSTRAINT FK_pit_stops_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.pit_stops ADD CONSTRAINT FK_pit_stops_drivers_driverId FOREIGN KEY ([driverId]) REFERENCES dbo.drivers ([driverId]);
ALTER TABLE dbo.driver_standings ADD CONSTRAINT FK_driver_standings_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.driver_standings ADD CONSTRAINT FK_driver_standings_drivers_driverId FOREIGN KEY ([driverId]) REFERENCES dbo.drivers ([driverId]);
ALTER TABLE dbo.constructor_standings ADD CONSTRAINT FK_constructor_standings_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.constructor_standings ADD CONSTRAINT FK_constructor_standings_constructors_constructorId FOREIGN KEY ([constructorId]) REFERENCES dbo.constructors ([constructorId]);
ALTER TABLE dbo.constructor_results ADD CONSTRAINT FK_constructor_results_races_raceId FOREIGN KEY ([raceId]) REFERENCES dbo.races ([raceId]);
ALTER TABLE dbo.constructor_results ADD CONSTRAINT FK_constructor_results_constructors_constructorId FOREIGN KEY ([constructorId]) REFERENCES dbo.constructors ([constructorId]);
GO

/* =========================== BƯỚC 5: KIỂM TRA =========================== */
SELECT t.TableName, t.ExpectedRows, t.LoadedRows,
       CASE WHEN t.ExpectedRows = t.LoadedRows THEN N'OK' ELSE N'SAI LỆCH' END AS KetQua
FROM (
    SELECT 'seasons' AS TableName, 75 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.seasons) AS LoadedRows
    UNION ALL
    SELECT 'circuits' AS TableName, 77 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.circuits) AS LoadedRows
    UNION ALL
    SELECT 'constructors' AS TableName, 212 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.constructors) AS LoadedRows
    UNION ALL
    SELECT 'drivers' AS TableName, 861 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.drivers) AS LoadedRows
    UNION ALL
    SELECT 'status' AS TableName, 139 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.status) AS LoadedRows
    UNION ALL
    SELECT 'races' AS TableName, 1125 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.races) AS LoadedRows
    UNION ALL
    SELECT 'results' AS TableName, 26759 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.results) AS LoadedRows
    UNION ALL
    SELECT 'sprint_results' AS TableName, 360 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.sprint_results) AS LoadedRows
    UNION ALL
    SELECT 'qualifying' AS TableName, 10494 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.qualifying) AS LoadedRows
    UNION ALL
    SELECT 'lap_times' AS TableName, 589081 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.lap_times) AS LoadedRows
    UNION ALL
    SELECT 'pit_stops' AS TableName, 11371 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.pit_stops) AS LoadedRows
    UNION ALL
    SELECT 'driver_standings' AS TableName, 34863 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.driver_standings) AS LoadedRows
    UNION ALL
    SELECT 'constructor_standings' AS TableName, 13391 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.constructor_standings) AS LoadedRows
    UNION ALL
    SELECT 'constructor_results' AS TableName, 12625 AS ExpectedRows, (SELECT COUNT(*) FROM dbo.constructor_results) AS LoadedRows
) t
ORDER BY t.TableName;

-- Xong bước nguồn thì có thể xoá bảng tạm (tuỳ chọn):
-- DROP TABLE stg.seasons, stg.circuits, ... ;
GO