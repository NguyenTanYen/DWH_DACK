/* =====================================================================
   F1_DWH – ETL BẰNG T-SQL (F1_SOURCE  →  F1_DWH), THEO KIMBALL
   ---------------------------------------------------------------------
   File này chỉ TẠO các thủ tục (stored procedure). Dòng cuối cùng
   EXEC etl.usp_Run_ETL sẽ chạy toàn bộ.

   Các kỹ thuật Kimball được dùng:
     - Surrogate key pipeline: thay mọi khoá tự nhiên bằng khoá thay thế
     - Point-in-time lookup cho chiều SCD Type 2 (theo ngày đua)
     - Unknown member (-1) khi tra khoá không thấy → fact không NULL FK
     - SCD Type 1 (MERGE ghi đè) và SCD Type 2 (đóng dòng cũ + thêm dòng mới)
     - Nạp fact tăng dần (incremental): chỉ thêm dòng chưa có → chạy lại an toàn
     - Accumulating snapshot: MERGE cập nhật dòng khi có mốc mới
     - Audit dimension: mỗi lần chạy = 1 dòng DimAudit, fact mang AuditKey
   Thứ tự: 00_create_f1_source.sql → 01_create_f1_dwh.sql → file này.
   ===================================================================== */
USE F1_DWH;
GO

/* =====================================================================
   0. VIEW TRA CỨU CHẶNG ĐUA (dùng chung cho mọi bảng fact)
   ===================================================================== */
CREATE OR ALTER VIEW etl.vw_RaceLookup
AS
SELECT  r.raceId                           AS RaceID,
        ISNULL(dr.RaceKey, -1)             AS RaceKey,
        ISNULL(dc.CircuitKey, -1)          AS CircuitKey,
        r.[date]                           AS RaceDate,
        CASE WHEN r.[date] IS NULL THEN -1
             ELSE YEAR(r.[date]) * 10000 + MONTH(r.[date]) * 100 + DAY(r.[date]) END AS RaceDateKey
FROM    F1_SOURCE.dbo.races r
LEFT JOIN dbo.DimRace    dr ON dr.RaceID    = r.raceId
LEFT JOIN dbo.DimCircuit dc ON dc.CircuitID = r.circuitId;
GO

/* =====================================================================
   1. CHIỀU
   ===================================================================== */

-- 1.1 DimDate: sinh mọi ngày trong khoảng (chỉ thêm ngày chưa có)
CREATE OR ALTER PROCEDURE etl.usp_Load_DimDate
    @StartDate DATE = '1950-01-01',
    @EndDate   DATE = '2030-12-31'
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH n AS (
        SELECT TOP (DATEDIFF(DAY, @StartDate, @EndDate) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ), d AS (
        SELECT DATEADD(DAY, i, @StartDate) AS dt,
               DATEDIFF(DAY, '19000101', DATEADD(DAY, i, @StartDate)) % 7 AS dow0  -- 0 = Thứ Hai
        FROM n
    )
    INSERT INTO dbo.DimDate (DateKey, FullDate, [Day], [Month], MonthName, [Quarter], [Year],
                             Decade, DayOfWeek, DayName, WeekdayWeekend)
    SELECT YEAR(dt) * 10000 + MONTH(dt) * 100 + DAY(dt),
           dt, DAY(dt), MONTH(dt), DATENAME(MONTH, dt), DATEPART(QUARTER, dt), YEAR(dt),
           CAST(YEAR(dt) / 10 * 10 AS NVARCHAR(4)) + N's',
           dow0 + 1, DATENAME(WEEKDAY, dt),
           CASE WHEN dow0 >= 5 THEN N'Weekend' ELSE N'Weekday' END
    FROM d
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DimDate x
                      WHERE x.DateKey = YEAR(d.dt) * 10000 + MONTH(d.dt) * 100 + DAY(d.dt));
END;
GO

-- 1.2 DimStatus: SCD Type 1 + gom nhóm trạng thái
CREATE OR ALTER PROCEDURE etl.usp_Load_DimStatus
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME2(0) = SYSDATETIME();

    MERGE dbo.DimStatus AS tgt
    USING (
        SELECT s.statusId, s.[status], g.StatusGroup,
               CASE WHEN g.StatusGroup IN (N'Finished', N'Finished (lapped)')
                    THEN N'Classified' ELSE N'Not classified' END AS FinishClassification
        FROM F1_SOURCE.dbo.[status] s
        CROSS APPLY (SELECT CASE
            WHEN s.[status] = N'Finished'                                   THEN N'Finished'
            WHEN s.[status] LIKE N'+% Lap%'                                 THEN N'Finished (lapped)'
            WHEN s.[status] IN (N'Disqualified', N'Excluded', N'Underweight') THEN N'Disqualified'
            WHEN s.[status] IN (N'Did not qualify', N'Did not prequalify', N'107% Rule',
                                N'Withdrew', N'Not restarted', N'Not classified')
                                                                            THEN N'Did not start / Not classified'
            WHEN (s.[status] LIKE N'%accident%' OR s.[status] LIKE N'%collision%'
                  OR s.[status] LIKE N'%spun off%' OR s.[status] LIKE N'%damage%'
                  OR s.[status] LIKE N'%debris%'   OR s.[status] LIKE N'%fire%')
                 AND s.[status] NOT LIKE N'%heat shield%'
                 AND s.[status] NOT LIKE N'%engine fire%'                  THEN N'Accident / Collision'
            WHEN s.[status] LIKE N'%injur%' OR s.[status] LIKE N'%illness%'
                 OR s.[status] LIKE N'%unwell%' OR s.[status] LIKE N'%physical%'
                 OR s.[status] LIKE N'%eye%'                               THEN N'Driver health'
            WHEN s.[status] IN (N'Retired', N'Safety', N'Safety concerns')  THEN N'Other'
            ELSE N'Mechanical / Technical' END AS StatusGroup) g
    ) AS src
    ON tgt.StatusID = src.statusId
    WHEN MATCHED AND EXISTS (SELECT src.[status], src.StatusGroup, src.FinishClassification
                             EXCEPT
                             SELECT tgt.StatusDesc, tgt.StatusGroup, tgt.FinishClassification)
        THEN UPDATE SET StatusDesc = src.[status], StatusGroup = src.StatusGroup,
                        FinishClassification = src.FinishClassification, RowUpdatedAt = @Now
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (StatusID, StatusDesc, StatusGroup, FinishClassification, RowInsertedAt, RowUpdatedAt)
             VALUES (src.statusId, src.[status], src.StatusGroup, src.FinishClassification, @Now, @Now);
END;
GO

-- 1.3 DimCircuit: SCD Type 1 + chuẩn hoá quốc gia + làm giàu châu lục
CREATE OR ALTER PROCEDURE etl.usp_Load_DimCircuit
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME2(0) = SYSDATETIME();

    MERGE dbo.DimCircuit AS tgt
    USING (
        SELECT c.circuitId, c.circuitRef, c.[name], ISNULL(c.[location], N'Unknown') AS City,
               x.Country, ISNULL(m.Continent, N'Europe') AS Continent, c.lat, c.lng, c.alt
        FROM F1_SOURCE.dbo.circuits c
        CROSS APPLY (SELECT CASE WHEN c.country = N'United States' THEN N'USA'
                                 ELSE ISNULL(c.country, N'Unknown') END AS Country) x
        LEFT JOIN etl.MapCountryContinent m ON m.Country = x.Country
    ) AS src
    ON tgt.CircuitID = src.circuitId
    WHEN MATCHED AND EXISTS (SELECT src.circuitRef, src.[name], src.City, src.Country, src.Continent, src.lat, src.lng, src.alt
                             EXCEPT
                             SELECT tgt.CircuitRef, tgt.CircuitName, tgt.City, tgt.Country, tgt.Continent, tgt.Latitude, tgt.Longitude, tgt.AltitudeM)
        THEN UPDATE SET CircuitRef = src.circuitRef, CircuitName = src.[name], City = src.City,
                        Country = src.Country, Continent = src.Continent, Latitude = src.lat,
                        Longitude = src.lng, AltitudeM = src.alt, RowUpdatedAt = @Now
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (CircuitID, CircuitRef, CircuitName, City, Country, Continent, Latitude, Longitude, AltitudeM, RowInsertedAt, RowUpdatedAt)
             VALUES (src.circuitId, src.circuitRef, src.[name], src.City, src.Country, src.Continent, src.lat, src.lng, src.alt, @Now, @Now);
END;
GO

-- 1.4 DimRace: SCD Type 1 (RoundsInSeason, IsSeasonFinale tính lại mỗi lần)
CREATE OR ALTER PROCEDURE etl.usp_Load_DimRace
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME2(0) = SYSDATETIME();

    MERGE dbo.DimRace AS tgt
    USING (
        SELECT r.raceId, r.[name], r.[year],
               CAST(r.[year] / 10 * 10 AS NVARCHAR(4)) + N's' AS Decade,
               r.[round],
               MAX(r.[round]) OVER (PARTITION BY r.[year]) AS RoundsInSeason,
               CASE WHEN r.[round] = MAX(r.[round]) OVER (PARTITION BY r.[year])
                    THEN N'Yes' ELSE N'No' END AS IsSeasonFinale,
               r.[date], r.[time],
               CASE WHEN r.sprint_date IS NOT NULL
                      OR EXISTS (SELECT 1 FROM F1_SOURCE.dbo.sprint_results s WHERE s.raceId = r.raceId)
                    THEN N'Sprint' ELSE N'Standard' END AS WeekendFormat
        FROM F1_SOURCE.dbo.races r
    ) AS src
    ON tgt.RaceID = src.raceId
    WHEN MATCHED AND EXISTS (SELECT src.[name], src.[year], src.[round], src.RoundsInSeason, src.IsSeasonFinale,
                                    src.[date], src.[time], src.WeekendFormat
                             EXCEPT
                             SELECT tgt.RaceName, tgt.Season, tgt.[Round], tgt.RoundsInSeason, tgt.IsSeasonFinale,
                                    tgt.RaceDate, tgt.RaceStartTimeUTC, tgt.WeekendFormat)
        THEN UPDATE SET RaceName = src.[name], Season = src.[year], Decade = src.Decade, [Round] = src.[round],
                        RoundsInSeason = src.RoundsInSeason, IsSeasonFinale = src.IsSeasonFinale,
                        RaceDate = src.[date], RaceStartTimeUTC = src.[time],
                        WeekendFormat = src.WeekendFormat, RowUpdatedAt = @Now
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (RaceID, RaceName, Season, Decade, [Round], RoundsInSeason, IsSeasonFinale,
                     RaceDate, RaceStartTimeUTC, WeekendFormat, RowInsertedAt, RowUpdatedAt)
             VALUES (src.raceId, src.[name], src.[year], src.Decade, src.[round], src.RoundsInSeason, src.IsSeasonFinale,
                     src.[date], src.[time], src.WeekendFormat, @Now, @Now);
END;
GO

-- 1.5 DimDriver: SCD Type 1 + Type 2
CREATE OR ALTER PROCEDURE etl.usp_Load_DimDriver
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME2(0) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);

    IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;
    SELECT  d.driverId                                          AS DriverID,
            d.driverRef                                         AS DriverRef,
            ISNULL(d.code, N'N/A')                              AS DriverCode,
            ISNULL(CAST(d.[number] AS NVARCHAR(3)), N'N/A')     AS PermanentNumber,
            d.forename                                          AS FirstName,
            d.surname                                           AS LastName,
            d.forename + N' ' + d.surname                       AS FullName,
            d.dob                                               AS DateOfBirth,
            ISNULL(LTRIM(RTRIM(d.nationality)), N'Unknown')     AS Nationality,
            ISNULL(m.Country, N'Unknown')                       AS NationalityCountry
    INTO    #src
    FROM    F1_SOURCE.dbo.drivers d
    LEFT JOIN etl.MapNationalityCountry m ON m.Nationality = LTRIM(RTRIM(d.nationality));

    -- (a) Type 1: ghi đè trên MỌI phiên bản của tay đua
    UPDATE t
    SET    DriverRef = s.DriverRef, FirstName = s.FirstName, LastName = s.LastName,
           FullName = s.FullName, DateOfBirth = s.DateOfBirth, RowUpdatedAt = @Now
    FROM   dbo.DimDriver t
    JOIN   #src s ON s.DriverID = t.DriverID
    WHERE  EXISTS (SELECT t.DriverRef, t.FirstName, t.LastName, t.DateOfBirth
                   EXCEPT
                   SELECT s.DriverRef, s.FirstName, s.LastName, s.DateOfBirth);

    -- (b) Type 2: đóng dòng hiện hành nếu thuộc tính Type 2 thay đổi
    UPDATE t
    SET    RowExpirationDate = DATEADD(DAY, -1, @Today),
           IsCurrentRow = N'Expired', RowUpdatedAt = @Now
    FROM   dbo.DimDriver t
    JOIN   #src s ON s.DriverID = t.DriverID
    WHERE  t.IsCurrentRow = N'Current'
      AND  EXISTS (SELECT t.DriverCode, t.PermanentNumber, t.Nationality, t.NationalityCountry
                   EXCEPT
                   SELECT s.DriverCode, s.PermanentNumber, s.Nationality, s.NationalityCountry);

    -- (c) Thêm dòng mới: tay đua mới (hiệu lực từ 1900-01-01) hoặc phiên bản mới (từ hôm nay)
    INSERT INTO dbo.DimDriver (DriverID, DriverRef, DriverCode, PermanentNumber, FirstName, LastName, FullName,
                               DateOfBirth, Nationality, NationalityCountry,
                               RowEffectiveDate, RowExpirationDate, IsCurrentRow, RowInsertedAt, RowUpdatedAt)
    SELECT s.DriverID, s.DriverRef, s.DriverCode, s.PermanentNumber, s.FirstName, s.LastName, s.FullName,
           s.DateOfBirth, s.Nationality, s.NationalityCountry,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.DimDriver x WHERE x.DriverID = s.DriverID)
                THEN @Today ELSE '1900-01-01' END,
           '9999-12-31', N'Current', @Now, @Now
    FROM   #src s
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.DimDriver t
                       WHERE t.DriverID = s.DriverID AND t.IsCurrentRow = N'Current');
END;
GO

-- 1.6 DimConstructor: Type 1 (ConstructorRef) + Type 2 (ConstructorName, Nationality)
CREATE OR ALTER PROCEDURE etl.usp_Load_DimConstructor
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME2(0) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);

    IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;
    SELECT  c.constructorId                                  AS ConstructorID,
            c.constructorRef                                 AS ConstructorRef,
            c.[name]                                         AS ConstructorName,
            ISNULL(LTRIM(RTRIM(c.nationality)), N'Unknown')  AS Nationality
    INTO    #src
    FROM    F1_SOURCE.dbo.constructors c;

    UPDATE t
    SET    ConstructorRef = s.ConstructorRef, RowUpdatedAt = @Now
    FROM   dbo.DimConstructor t
    JOIN   #src s ON s.ConstructorID = t.ConstructorID
    WHERE  t.ConstructorRef <> s.ConstructorRef;

    UPDATE t
    SET    RowExpirationDate = DATEADD(DAY, -1, @Today),
           IsCurrentRow = N'Expired', RowUpdatedAt = @Now
    FROM   dbo.DimConstructor t
    JOIN   #src s ON s.ConstructorID = t.ConstructorID
    WHERE  t.IsCurrentRow = N'Current'
      AND  EXISTS (SELECT t.ConstructorName, t.Nationality
                   EXCEPT
                   SELECT s.ConstructorName, s.Nationality);

    INSERT INTO dbo.DimConstructor (ConstructorID, ConstructorRef, ConstructorName, Nationality,
                                    RowEffectiveDate, RowExpirationDate, IsCurrentRow, RowInsertedAt, RowUpdatedAt)
    SELECT s.ConstructorID, s.ConstructorRef, s.ConstructorName, s.Nationality,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.DimConstructor x WHERE x.ConstructorID = s.ConstructorID)
                THEN @Today ELSE '1900-01-01' END,
           '9999-12-31', N'Current', @Now, @Now
    FROM   #src s
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.DimConstructor t
                       WHERE t.ConstructorID = s.ConstructorID AND t.IsCurrentRow = N'Current');
END;
GO

/* =====================================================================
   2. FACT – nạp tăng dần, tra khoá thay thế (point-in-time cho SCD2)
   ===================================================================== */

-- 2.1 FactRaceResult (Grand Prix + Sprint)
CREATE OR ALTER PROCEDURE etl.usp_Load_FactRaceResult
    @AuditKey INT, @Rows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH src AS (
        SELECT 1 AS SessionTypeKey, resultId, raceId, driverId, constructorId, [number], grid, position,
               positionOrder, points, laps, milliseconds, fastestLap, [rank], fastestLapTime,
               fastestLapSpeed, statusId
        FROM F1_SOURCE.dbo.results
        UNION ALL
        SELECT 2, resultId, raceId, driverId, constructorId, [number], grid, position,
               positionOrder, points, laps, milliseconds, fastestLap, NULL, fastestLapTime,
               NULL, statusId
        FROM F1_SOURCE.dbo.sprint_results
    )
    INSERT INTO dbo.FactRaceResult (
        RaceDateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, StatusKey, SessionTypeKey, AuditKey,
        ResultID, CarNumber, GridPosition, FinishPosition, PositionOrder, Points, LapsCompleted,
        RaceTimeMs, FastestLapNumber, FastestLapRank, FastestLapTimeMs, FastestLapSpeedKph,
        DriverAgeAtRace, PositionsGained,
        WinCount, PodiumCount, PoleCount, PointsFinishCount, DNFCount, HomeRaceCount)
    SELECT  ISNULL(rl.RaceDateKey, -1), ISNULL(rl.RaceKey, -1), ISNULL(rl.CircuitKey, -1),
            ISNULL(dd.DriverKey, -1), ISNULL(dk.ConstructorKey, -1), ISNULL(ds.StatusKey, -1),
            s.SessionTypeKey, @AuditKey,
            s.resultId, s.[number], s.grid, s.position, s.positionOrder, s.points, s.laps,
            s.milliseconds, s.fastestLap, s.[rank], etl.fn_TimeToMs(s.fastestLapTime), s.fastestLapSpeed,
            CAST(DATEDIFF(DAY, dd.DateOfBirth, rl.RaceDate) / 365.25 AS DECIMAL(4,1)),
            CASE WHEN s.grid > 0 THEN s.grid - s.positionOrder END,
            CASE WHEN s.position = 1 THEN 1 ELSE 0 END,
            CASE WHEN s.position <= 3 THEN 1 ELSE 0 END,
            CASE WHEN s.grid = 1 THEN 1 ELSE 0 END,
            CASE WHEN s.points > 0 THEN 1 ELSE 0 END,
            CASE WHEN ds.FinishClassification = N'Classified' THEN 0 ELSE 1 END,
            CASE WHEN dd.NationalityCountry = dc.Country THEN 1 ELSE 0 END
    FROM    src s
    LEFT JOIN etl.vw_RaceLookup rl ON rl.RaceID = s.raceId
    LEFT JOIN dbo.DimCircuit    dc ON dc.CircuitKey = rl.CircuitKey
    LEFT JOIN dbo.DimDriver     dd ON dd.DriverID = s.driverId
                                  AND rl.RaceDate BETWEEN dd.RowEffectiveDate AND dd.RowExpirationDate
    LEFT JOIN dbo.DimConstructor dk ON dk.ConstructorID = s.constructorId
                                  AND rl.RaceDate BETWEEN dk.RowEffectiveDate AND dk.RowExpirationDate
    LEFT JOIN dbo.DimStatus     ds ON ds.StatusID = s.statusId
    WHERE NOT EXISTS (SELECT 1 FROM dbo.FactRaceResult f
                      WHERE f.SessionTypeKey = s.SessionTypeKey AND f.ResultID = s.resultId);
    SET @Rows = @@ROWCOUNT;
END;
GO

-- 2.2 FactQualifying
CREATE OR ALTER PROCEDURE etl.usp_Load_FactQualifying
    @AuditKey INT, @Rows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH q AS (
        SELECT qualifyId, raceId, driverId, constructorId, position,
               etl.fn_TimeToMs(q1) AS Q1Ms, etl.fn_TimeToMs(q2) AS Q2Ms, etl.fn_TimeToMs(q3) AS Q3Ms
        FROM F1_SOURCE.dbo.qualifying
    ), qb AS (
        SELECT q.*, b.BestLapMs
        FROM q
        CROSS APPLY (SELECT MIN(v) AS BestLapMs FROM (VALUES (q.Q1Ms), (q.Q2Ms), (q.Q3Ms)) x(v)) b
    ), qp AS (
        SELECT qb.*, MIN(qb.BestLapMs) OVER (PARTITION BY qb.raceId) AS PoleMs
        FROM qb
    )
    INSERT INTO dbo.FactQualifying (
        RaceDateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, AuditKey, QualifyID,
        QualiPosition, Q1Ms, Q2Ms, Q3Ms, BestLapMs, GapToPoleMs, GapToPolePct, ReachedQ2Count, ReachedQ3Count)
    SELECT  ISNULL(rl.RaceDateKey, -1), ISNULL(rl.RaceKey, -1), ISNULL(rl.CircuitKey, -1),
            ISNULL(dd.DriverKey, -1), ISNULL(dk.ConstructorKey, -1), @AuditKey, qp.qualifyId,
            qp.position, qp.Q1Ms, qp.Q2Ms, qp.Q3Ms, qp.BestLapMs,
            qp.BestLapMs - qp.PoleMs,
            CAST((qp.BestLapMs - qp.PoleMs) * 100.0 / NULLIF(qp.PoleMs, 0) AS DECIMAL(7,3)),
            CASE WHEN qp.Q2Ms IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN qp.Q3Ms IS NOT NULL THEN 1 ELSE 0 END
    FROM    qp
    LEFT JOIN etl.vw_RaceLookup  rl ON rl.RaceID = qp.raceId
    LEFT JOIN dbo.DimDriver      dd ON dd.DriverID = qp.driverId
                                   AND rl.RaceDate BETWEEN dd.RowEffectiveDate AND dd.RowExpirationDate
    LEFT JOIN dbo.DimConstructor dk ON dk.ConstructorID = qp.constructorId
                                   AND rl.RaceDate BETWEEN dk.RowEffectiveDate AND dk.RowExpirationDate
    WHERE NOT EXISTS (SELECT 1 FROM dbo.FactQualifying f WHERE f.QualifyID = qp.qualifyId);
    SET @Rows = @@ROWCOUNT;
END;
GO

-- 2.3 FactLapTime (đội đua lấy từ results theo cặp chặng + tay đua)
CREATE OR ALTER PROCEDURE etl.usp_Load_FactLapTime
    @AuditKey INT, @Rows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH drv_team AS (
        SELECT raceId, driverId, MIN(constructorId) AS constructorId
        FROM F1_SOURCE.dbo.results
        GROUP BY raceId, driverId
    ), src AS (
        SELECT  ISNULL(rl.RaceDateKey, -1)      AS RaceDateKey,
                ISNULL(rl.RaceKey, -1)          AS RaceKey,
                ISNULL(rl.CircuitKey, -1)       AS CircuitKey,
                ISNULL(dd.DriverKey, -1)        AS DriverKey,
                ISNULL(dk.ConstructorKey, -1)   AS ConstructorKey,
                l.lap, l.position, l.milliseconds
        FROM    F1_SOURCE.dbo.lap_times l
        LEFT JOIN etl.vw_RaceLookup  rl ON rl.RaceID = l.raceId
        LEFT JOIN drv_team           t  ON t.raceId = l.raceId AND t.driverId = l.driverId
        LEFT JOIN dbo.DimDriver      dd ON dd.DriverID = l.driverId
                                       AND rl.RaceDate BETWEEN dd.RowEffectiveDate AND dd.RowExpirationDate
        LEFT JOIN dbo.DimConstructor dk ON dk.ConstructorID = t.constructorId
                                       AND rl.RaceDate BETWEEN dk.RowEffectiveDate AND dk.RowExpirationDate
    )
    INSERT INTO dbo.FactLapTime (RaceDateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, AuditKey,
                                 LapNumber, PositionOnLap, LapTimeMs)
    SELECT RaceDateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, @AuditKey, lap, position, milliseconds
    FROM   src
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.FactLapTime f
                       WHERE f.RaceKey = src.RaceKey AND f.DriverKey = src.DriverKey AND f.LapNumber = src.lap);
    SET @Rows = @@ROWCOUNT;
END;
GO

-- 2.4 FactPitStop
CREATE OR ALTER PROCEDURE etl.usp_Load_FactPitStop
    @AuditKey INT, @Rows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH drv_team AS (
        SELECT raceId, driverId, MIN(constructorId) AS constructorId
        FROM F1_SOURCE.dbo.results
        GROUP BY raceId, driverId
    ), src AS (
        SELECT  ISNULL(rl.RaceDateKey, -1)      AS RaceDateKey,
                ISNULL(rl.RaceKey, -1)          AS RaceKey,
                ISNULL(rl.CircuitKey, -1)       AS CircuitKey,
                ISNULL(dd.DriverKey, -1)        AS DriverKey,
                ISNULL(dk.ConstructorKey, -1)   AS ConstructorKey,
                p.[stop], p.lap, p.[time], p.milliseconds
        FROM    F1_SOURCE.dbo.pit_stops p
        LEFT JOIN etl.vw_RaceLookup  rl ON rl.RaceID = p.raceId
        LEFT JOIN drv_team           t  ON t.raceId = p.raceId AND t.driverId = p.driverId
        LEFT JOIN dbo.DimDriver      dd ON dd.DriverID = p.driverId
                                       AND rl.RaceDate BETWEEN dd.RowEffectiveDate AND dd.RowExpirationDate
        LEFT JOIN dbo.DimConstructor dk ON dk.ConstructorID = t.constructorId
                                       AND rl.RaceDate BETWEEN dk.RowEffectiveDate AND dk.RowExpirationDate
    )
    INSERT INTO dbo.FactPitStop (RaceDateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, AuditKey,
                                 StopNumber, LapNumber, StopTimeOfDay, PitLaneTimeMs, OutlierCount)
    SELECT RaceDateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, @AuditKey,
           [stop], lap, [time], milliseconds,
           CASE WHEN milliseconds > 60000 THEN 1 ELSE 0 END
    FROM   src
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.FactPitStop f
                       WHERE f.RaceKey = src.RaceKey AND f.DriverKey = src.DriverKey AND f.StopNumber = src.[stop]);
    SET @Rows = @@ROWCOUNT;
END;
GO

-- 2.5 Periodic snapshot: bảng xếp hạng tay đua
CREATE OR ALTER PROCEDURE etl.usp_Load_FactDriverStandingSnapshot
    @AuditKey INT, @Rows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH src AS (
        SELECT  ISNULL(rl.RaceDateKey, -1) AS RaceDateKey,
                ISNULL(rl.RaceKey, -1)     AS RaceKey,
                ISNULL(dd.DriverKey, -1)   AS DriverKey,
                s.position, s.points, s.wins
        FROM    F1_SOURCE.dbo.driver_standings s
        LEFT JOIN etl.vw_RaceLookup rl ON rl.RaceID = s.raceId
        LEFT JOIN dbo.DimDriver     dd ON dd.DriverID = s.driverId
                                      AND rl.RaceDate BETWEEN dd.RowEffectiveDate AND dd.RowExpirationDate
    )
    INSERT INTO dbo.FactDriverStandingSnapshot (RaceDateKey, RaceKey, DriverKey, AuditKey,
                                                StandingPosition, CumulativePoints, CumulativeWins)
    SELECT RaceDateKey, RaceKey, DriverKey, @AuditKey, position, points, wins
    FROM   src
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.FactDriverStandingSnapshot f
                       WHERE f.RaceKey = src.RaceKey AND f.DriverKey = src.DriverKey);
    SET @Rows = @@ROWCOUNT;
END;
GO

-- 2.6 Periodic snapshot: bảng xếp hạng đội đua
CREATE OR ALTER PROCEDURE etl.usp_Load_FactConstructorStandingSnapshot
    @AuditKey INT, @Rows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH src AS (
        SELECT  ISNULL(rl.RaceDateKey, -1)    AS RaceDateKey,
                ISNULL(rl.RaceKey, -1)        AS RaceKey,
                ISNULL(dk.ConstructorKey, -1) AS ConstructorKey,
                s.position, s.points, s.wins
        FROM    F1_SOURCE.dbo.constructor_standings s
        LEFT JOIN etl.vw_RaceLookup  rl ON rl.RaceID = s.raceId
        LEFT JOIN dbo.DimConstructor dk ON dk.ConstructorID = s.constructorId
                                       AND rl.RaceDate BETWEEN dk.RowEffectiveDate AND dk.RowExpirationDate
    )
    INSERT INTO dbo.FactConstructorStandingSnapshot (RaceDateKey, RaceKey, ConstructorKey, AuditKey,
                                                     StandingPosition, CumulativePoints, CumulativeWins)
    SELECT RaceDateKey, RaceKey, ConstructorKey, @AuditKey, position, points, wins
    FROM   src
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.FactConstructorStandingSnapshot f
                       WHERE f.RaceKey = src.RaceKey AND f.ConstructorKey = src.ConstructorKey);
    SET @Rows = @@ROWCOUNT;
END;
GO

-- 2.7 Accumulating snapshot: cuối tuần đua (thêm mới HOẶC cập nhật khi có mốc mới)
--     Được tổng hợp từ các fact giao dịch đã nạp ở trên.
CREATE OR ALTER PROCEDURE etl.usp_Load_FactRaceWeekend
    @AuditKey INT, @Rows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('tempdb..#wk') IS NOT NULL DROP TABLE #wk;

    SELECT  dr.RaceKey,
            ISNULL(dc.CircuitKey, -1)             AS CircuitKey,
            etl.fn_DateKey(r.fp1_date)            AS FP1DateKey,
            etl.fn_DateKey(r.quali_date)          AS QualifyingDateKey,
            etl.fn_DateKey(r.sprint_date)         AS SprintDateKey,
            etl.fn_DateKey(r.[date])              AS RaceDateKey,
            ISNULL(pole.DriverKey, -1)            AS PoleSitterDriverKey,
            ISNULL(win.DriverKey, -1)             AS WinnerDriverKey,
            ISNULL(fl.DriverKey, -1)              AS FastestLapDriverKey,
            ISNULL(win.ConstructorKey, -1)        AS WinnerConstructorKey,
            NULLIF(a.EntrantCount, 0)             AS EntrantCount,
            a.ClassifiedCount, a.DNFCount, a.RaceLaps,
            win.RaceTimeMs                        AS WinnerRaceTimeMs,
            CAST(p2.RaceTimeMs - win.RaceTimeMs AS INT) AS WinningMarginMs,
            q.PoleLapMs,
            NULLIF(ps.PitStopCount, 0)            AS PitStopCount,
            DATEDIFF(DAY, r.fp1_date, r.[date])   AS DaysFP1ToRace,
            CAST(CASE WHEN pole.DriverKey IS NULL OR win.DriverKey IS NULL THEN NULL
                      WHEN pole.DriverKey = win.DriverKey THEN 1 ELSE 0 END AS TINYINT) AS PoleConvertedCount
    INTO    #wk
    FROM    F1_SOURCE.dbo.races r
    JOIN    dbo.DimRace    dr ON dr.RaceID = r.raceId
    LEFT JOIN dbo.DimCircuit dc ON dc.CircuitID = r.circuitId
    OUTER APPLY (SELECT COUNT(*) AS EntrantCount,
                        SUM(CASE WHEN f.DNFCount = 0 THEN 1 ELSE 0 END) AS ClassifiedCount,
                        SUM(CAST(f.DNFCount AS INT)) AS DNFCount,
                        MAX(f.LapsCompleted) AS RaceLaps
                 FROM dbo.FactRaceResult f
                 WHERE f.RaceKey = dr.RaceKey AND f.SessionTypeKey = 1) a
    OUTER APPLY (SELECT TOP (1) f.DriverKey, f.ConstructorKey, f.RaceTimeMs
                 FROM dbo.FactRaceResult f
                 WHERE f.RaceKey = dr.RaceKey AND f.SessionTypeKey = 1 AND f.FinishPosition = 1
                 ORDER BY f.ResultID) win
    OUTER APPLY (SELECT TOP (1) f.RaceTimeMs
                 FROM dbo.FactRaceResult f
                 WHERE f.RaceKey = dr.RaceKey AND f.SessionTypeKey = 1 AND f.FinishPosition = 2
                 ORDER BY f.ResultID) p2
    OUTER APPLY (SELECT TOP (1) f.DriverKey
                 FROM dbo.FactRaceResult f
                 WHERE f.RaceKey = dr.RaceKey AND f.SessionTypeKey = 1 AND f.GridPosition = 1
                 ORDER BY f.ResultID) pole
    OUTER APPLY (SELECT TOP (1) f.DriverKey
                 FROM dbo.FactRaceResult f
                 WHERE f.RaceKey = dr.RaceKey AND f.SessionTypeKey = 1 AND f.FastestLapRank = 1
                 ORDER BY f.ResultID) fl
    OUTER APPLY (SELECT MIN(fq.BestLapMs) AS PoleLapMs
                 FROM dbo.FactQualifying fq
                 WHERE fq.RaceKey = dr.RaceKey AND fq.QualiPosition = 1) q
    OUTER APPLY (SELECT COUNT(*) AS PitStopCount
                 FROM dbo.FactPitStop fp
                 WHERE fp.RaceKey = dr.RaceKey) ps;

    MERGE dbo.FactRaceWeekend AS tgt
    USING #wk AS src
    ON tgt.RaceKey = src.RaceKey
    WHEN MATCHED AND EXISTS (
            SELECT src.CircuitKey, src.FP1DateKey, src.QualifyingDateKey, src.SprintDateKey, src.RaceDateKey,
                   src.PoleSitterDriverKey, src.WinnerDriverKey, src.FastestLapDriverKey, src.WinnerConstructorKey,
                   src.EntrantCount, src.ClassifiedCount, src.DNFCount, src.RaceLaps, src.WinnerRaceTimeMs,
                   src.WinningMarginMs, src.PoleLapMs, src.PitStopCount, src.DaysFP1ToRace, src.PoleConvertedCount
            EXCEPT
            SELECT tgt.CircuitKey, tgt.FP1DateKey, tgt.QualifyingDateKey, tgt.SprintDateKey, tgt.RaceDateKey,
                   tgt.PoleSitterDriverKey, tgt.WinnerDriverKey, tgt.FastestLapDriverKey, tgt.WinnerConstructorKey,
                   tgt.EntrantCount, tgt.ClassifiedCount, tgt.DNFCount, tgt.RaceLaps, tgt.WinnerRaceTimeMs,
                   tgt.WinningMarginMs, tgt.PoleLapMs, tgt.PitStopCount, tgt.DaysFP1ToRace, tgt.PoleConvertedCount)
        THEN UPDATE SET
            CircuitKey = src.CircuitKey, FP1DateKey = src.FP1DateKey, QualifyingDateKey = src.QualifyingDateKey,
            SprintDateKey = src.SprintDateKey, RaceDateKey = src.RaceDateKey,
            PoleSitterDriverKey = src.PoleSitterDriverKey, WinnerDriverKey = src.WinnerDriverKey,
            FastestLapDriverKey = src.FastestLapDriverKey, WinnerConstructorKey = src.WinnerConstructorKey,
            AuditKey = @AuditKey,
            EntrantCount = src.EntrantCount, ClassifiedCount = src.ClassifiedCount, DNFCount = src.DNFCount,
            RaceLaps = src.RaceLaps, WinnerRaceTimeMs = src.WinnerRaceTimeMs, WinningMarginMs = src.WinningMarginMs,
            PoleLapMs = src.PoleLapMs, PitStopCount = src.PitStopCount, DaysFP1ToRace = src.DaysFP1ToRace,
            PoleConvertedCount = src.PoleConvertedCount
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (RaceKey, CircuitKey, FP1DateKey, QualifyingDateKey, SprintDateKey, RaceDateKey,
                     PoleSitterDriverKey, WinnerDriverKey, FastestLapDriverKey, WinnerConstructorKey, AuditKey,
                     EntrantCount, ClassifiedCount, DNFCount, RaceLaps, WinnerRaceTimeMs, WinningMarginMs,
                     PoleLapMs, PitStopCount, DaysFP1ToRace, PoleConvertedCount)
             VALUES (src.RaceKey, src.CircuitKey, src.FP1DateKey, src.QualifyingDateKey, src.SprintDateKey, src.RaceDateKey,
                     src.PoleSitterDriverKey, src.WinnerDriverKey, src.FastestLapDriverKey, src.WinnerConstructorKey, @AuditKey,
                     src.EntrantCount, src.ClassifiedCount, src.DNFCount, src.RaceLaps, src.WinnerRaceTimeMs, src.WinningMarginMs,
                     src.PoleLapMs, src.PitStopCount, src.DaysFP1ToRace, src.PoleConvertedCount);
    SET @Rows = @@ROWCOUNT;
END;
GO

/* =====================================================================
   3. THỦ TỤC ĐIỀU PHỐI – ghi DimAudit, chạy chiều trước, fact sau
   ===================================================================== */
CREATE OR ALTER PROCEDURE etl.usp_Run_ETL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AuditKey INT, @n INT, @Total INT = 0;

    INSERT INTO dbo.DimAudit (EtlBatchName, SourceSystem, BatchStartTime, BatchStatus)
    VALUES (N'F1 incremental load', N'F1_SOURCE', SYSDATETIME(), N'Running');
    SET @AuditKey = SCOPE_IDENTITY();

    BEGIN TRY
        PRINT N'--- Nạp chiều ---';
        EXEC etl.usp_Load_DimDate;
        EXEC etl.usp_Load_DimStatus;
        EXEC etl.usp_Load_DimCircuit;
        EXEC etl.usp_Load_DimRace;
        EXEC etl.usp_Load_DimDriver;
        EXEC etl.usp_Load_DimConstructor;

        PRINT N'--- Nạp fact ---';
        EXEC etl.usp_Load_FactRaceResult                @AuditKey, @n OUTPUT; SET @Total += @n; PRINT N'FactRaceResult: '                  + CAST(@n AS NVARCHAR(12));
        EXEC etl.usp_Load_FactQualifying                @AuditKey, @n OUTPUT; SET @Total += @n; PRINT N'FactQualifying: '                  + CAST(@n AS NVARCHAR(12));
        EXEC etl.usp_Load_FactLapTime                   @AuditKey, @n OUTPUT; SET @Total += @n; PRINT N'FactLapTime: '                     + CAST(@n AS NVARCHAR(12));
        EXEC etl.usp_Load_FactPitStop                   @AuditKey, @n OUTPUT; SET @Total += @n; PRINT N'FactPitStop: '                     + CAST(@n AS NVARCHAR(12));
        EXEC etl.usp_Load_FactDriverStandingSnapshot    @AuditKey, @n OUTPUT; SET @Total += @n; PRINT N'FactDriverStandingSnapshot: '      + CAST(@n AS NVARCHAR(12));
        EXEC etl.usp_Load_FactConstructorStandingSnapshot @AuditKey, @n OUTPUT; SET @Total += @n; PRINT N'FactConstructorStandingSnapshot: ' + CAST(@n AS NVARCHAR(12));
        EXEC etl.usp_Load_FactRaceWeekend               @AuditKey, @n OUTPUT; SET @Total += @n; PRINT N'FactRaceWeekend (insert+update): ' + CAST(@n AS NVARCHAR(12));

        UPDATE dbo.DimAudit
        SET BatchEndTime = SYSDATETIME(), BatchStatus = N'Succeeded', RowsInserted = @Total
        WHERE AuditKey = @AuditKey;
    END TRY
    BEGIN CATCH
        UPDATE dbo.DimAudit
        SET BatchEndTime = SYSDATETIME(), BatchStatus = N'Failed', ErrorMessage = ERROR_MESSAGE()
        WHERE AuditKey = @AuditKey;
        THROW;
    END CATCH;

    -- Báo cáo nhanh sau khi chạy
    SELECT t.TableName, t.[Rows] FROM (VALUES
        (N'DimDate',                         (SELECT COUNT(*) FROM dbo.DimDate)),
        (N'DimCircuit',                      (SELECT COUNT(*) FROM dbo.DimCircuit)),
        (N'DimRace',                         (SELECT COUNT(*) FROM dbo.DimRace)),
        (N'DimDriver',                       (SELECT COUNT(*) FROM dbo.DimDriver)),
        (N'DimConstructor',                  (SELECT COUNT(*) FROM dbo.DimConstructor)),
        (N'DimStatus',                       (SELECT COUNT(*) FROM dbo.DimStatus)),
        (N'FactRaceResult',                  (SELECT COUNT(*) FROM dbo.FactRaceResult)),
        (N'FactQualifying',                  (SELECT COUNT(*) FROM dbo.FactQualifying)),
        (N'FactLapTime',                     (SELECT COUNT(*) FROM dbo.FactLapTime)),
        (N'FactPitStop',                     (SELECT COUNT(*) FROM dbo.FactPitStop)),
        (N'FactDriverStandingSnapshot',      (SELECT COUNT(*) FROM dbo.FactDriverStandingSnapshot)),
        (N'FactConstructorStandingSnapshot', (SELECT COUNT(*) FROM dbo.FactConstructorStandingSnapshot)),
        (N'FactRaceWeekend',                 (SELECT COUNT(*) FROM dbo.FactRaceWeekend))
    ) t(TableName, [Rows]);

    SELECT * FROM dbo.DimAudit WHERE AuditKey = @AuditKey;
END;
GO

/* =====================================================================
   4. CHẠY ETL
   ===================================================================== */
EXEC etl.usp_Run_ETL;
GO
