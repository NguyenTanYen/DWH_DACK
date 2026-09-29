 /* =====================================================================
   BƯỚC 3 – ETL: LẤY DỮ LIỆU TỪ F1_SOURCE, BIẾN ĐỔI VÀ NẠP VÀO F1_DWH
   ---------------------------------------------------------------------
   ETL = Extract (trích xuất) – Transform (biến đổi) – Load (nạp).
   Thứ tự bắt buộc: nạp BẢNG CHIỀU trước, BẢNG SỰ KIỆN sau,
   vì bảng sự kiện cần tra khoá (…Key) từ bảng chiều.
   Chạy file này SAU file 01. Muốn chạy lại từ đầu: chạy lại file 01 rồi file này.
   ===================================================================== */
USE F1_DWH;
GO
SET NOCOUNT ON;

/* =====================================================================
   PHẦN 1. NẠP CÁC BẢNG CHIỀU
   ===================================================================== */

-- 1.1 DimDate: sinh lần lượt từng ngày từ 01/01/1950 đến 31/12/2024
DECLARE @ngay DATE = '1950-01-01';
BEGIN TRANSACTION;
WHILE @ngay <= '2024-12-31'
BEGIN
    INSERT INTO DimDate (DateKey, FullDate, [Day], [Month], [Quarter], [Year], Decade)
    VALUES (YEAR(@ngay) * 10000 + MONTH(@ngay) * 100 + DAY(@ngay),   -- 20240302
            @ngay, DAY(@ngay), MONTH(@ngay), DATEPART(QUARTER, @ngay)
            , YEAR(@ngay),
            CAST(YEAR(@ngay) / 10 * 10 AS NVARCHAR(4)) + N's');         -- 2024 → '2020s'
    SET @ngay = DATEADD(DAY, 1, @ngay);
END
COMMIT;
PRINT N'Đã nạp DimDate';

-- 1.2 DimRace: mỗi chặng đua một dòng
INSERT INTO DimRace (RaceID, RaceName, Season, [Round])
SELECT raceId, [name], [year], [round]
FROM F1_SOURCE.dbo.races
ORDER BY [year], [round];

-- 1.3 DimCircuit: chuẩn hoá tên quốc gia ('United States' và 'USA' là một)
INSERT INTO DimCircuit (CircuitID, CircuitName, City, Country)
SELECT circuitId, [name], [location],
       CASE WHEN country = N'United States' THEN N'USA' ELSE country END
FROM F1_SOURCE.dbo.circuits;

-- 1.4 DimDriver: ghép họ và tên, bỏ khoảng trắng thừa ở quốc tịch
INSERT INTO DimDriver (DriverID, DriverCode, FullName, DateOfBirth, Nationality)
SELECT driverId, code, forename + N' ' + surname, dob, LTRIM(RTRIM(nationality))
FROM F1_SOURCE.dbo.drivers;

-- 1.5 DimConstructor
INSERT INTO DimConstructor (ConstructorID, ConstructorName, Nationality)
SELECT constructorId, [name], LTRIM(RTRIM(nationality))
FROM F1_SOURCE.dbo.constructors;

-- 1.6 DimStatus: gom 139 trạng thái thành 3 nhóm dễ phân tích
INSERT INTO DimStatus (StatusID, StatusName, StatusGroup)
SELECT statusId, [status],
       CASE WHEN [status] = N'Finished'     THEN N'Hoàn thành'
            WHEN [status] LIKE N'+%Lap%'    THEN N'Hoàn thành (bị bắt vòng)'  -- ví dụ '+1 Lap', '+2 Laps'
            ELSE N'Không hoàn thành'                                          -- hỏng máy, tai nạn, bị loại...
       END
FROM F1_SOURCE.dbo.[status];
PRINT N'Đã nạp các bảng chiều';
GO

/* =====================================================================
   PHẦN 2. NẠP CÁC BẢNG SỰ KIỆN
   Cách làm chung: lấy từng dòng ở bảng nguồn, JOIN với các bảng chiều
   theo MÃ GỐC (…ID) để lấy KHOÁ CỦA KHO (…Key), rồi tính các độ đo.
   ===================================================================== */

-- 2.1 FactRaceResult: từ bảng results
INSERT INTO FactRaceResult (ResultID, DateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, StatusKey,
                            GridPosition, FinishPosition, Points, LapsCompleted, RaceTimeMs, FastestLapTimeMs,
                            IsWin, IsPodium, IsFinished)
SELECT  r.resultId,
        YEAR(ra.[date]) * 10000 + MONTH(ra.[date]) * 100 + DAY(ra.[date]),   -- DateKey của ngày đua
        dr.RaceKey, dc.CircuitKey, dd.DriverKey, dk.ConstructorKey, ds.StatusKey,
        r.grid, r.position, r.points, r.laps, r.milliseconds,
        dbo.fn_DoiThoiGianSangMs(r.fastestLapTime),                         -- '1:34.722' → 94722
        CASE WHEN r.position = 1  THEN 1 ELSE 0 END,                         -- thắng
        CASE WHEN r.position <= 3 THEN 1 ELSE 0 END,                         -- lên bục
        CASE WHEN ds.StatusGroup = N'Không hoàn thành' THEN 0 ELSE 1 END     -- hoàn thành
FROM F1_SOURCE.dbo.results r
JOIN F1_SOURCE.dbo.races ra ON ra.raceId        = r.raceId
JOIN DimRace         dr     ON dr.RaceID        = r.raceId
JOIN DimCircuit      dc     ON dc.CircuitID     = ra.circuitId
JOIN DimDriver       dd     ON dd.DriverID      = r.driverId
JOIN DimConstructor  dk     ON dk.ConstructorID = r.constructorId
JOIN DimStatus       ds     ON ds.StatusID      = r.statusId;
PRINT N'Đã nạp FactRaceResult';

-- 2.2 FactQualifying: từ bảng qualifying
WITH q AS (
    SELECT qualifyId, raceId, driverId, constructorId, position,
           dbo.fn_DoiThoiGianSangMs(q1) AS Q1Ms,
           dbo.fn_DoiThoiGianSangMs(q2) AS Q2Ms,
           dbo.fn_DoiThoiGianSangMs(q3) AS Q3Ms
    FROM F1_SOURCE.dbo.qualifying
)
INSERT INTO FactQualifying (QualifyID, DateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey,
                            QualiPosition, Q1Ms, Q2Ms, Q3Ms, BestLapMs)
SELECT  q.qualifyId,
        YEAR(ra.[date]) * 10000 + MONTH(ra.[date]) * 100 + DAY(ra.[date]),
        dr.RaceKey, dc.CircuitKey, dd.DriverKey, dk.ConstructorKey,
        q.position, q.Q1Ms, q.Q2Ms, q.Q3Ms,
        (SELECT MIN(v) FROM (VALUES (q.Q1Ms), (q.Q2Ms), (q.Q3Ms)) AS t(v))   -- thời gian nhỏ nhất trong 3 vòng
FROM q
JOIN F1_SOURCE.dbo.races ra ON ra.raceId        = q.raceId
JOIN DimRace         dr     ON dr.RaceID        = q.raceId
JOIN DimCircuit      dc     ON dc.CircuitID     = ra.circuitId
JOIN DimDriver       dd     ON dd.DriverID      = q.driverId
JOIN DimConstructor  dk     ON dk.ConstructorID = q.constructorId;
PRINT N'Đã nạp FactQualifying';

-- 2.3 FactLapTime: từ bảng lap_times (bảng lớn nhất, khoảng 589 nghìn dòng)
INSERT INTO FactLapTime (DateKey, RaceKey, CircuitKey, DriverKey, LapNumber, PositionOnLap, LapTimeMs)
SELECT  YEAR(ra.[date]) * 10000 + MONTH(ra.[date]) * 100 + DAY(ra.[date]),
        dr.RaceKey, dc.CircuitKey, dd.DriverKey,
        l.lap, l.position, l.milliseconds
FROM F1_SOURCE.dbo.lap_times l
JOIN F1_SOURCE.dbo.races ra ON ra.raceId    = l.raceId
JOIN DimRace         dr     ON dr.RaceID    = l.raceId
JOIN DimCircuit      dc     ON dc.CircuitID = ra.circuitId
JOIN DimDriver       dd     ON dd.DriverID  = l.driverId;
PRINT N'Đã nạp FactLapTime';

-- 2.4 FactPitStop: bảng pit_stops KHÔNG có đội đua,
--     nên lấy đội của tay đua ở chặng đó từ bảng results
WITH doi_cua_tay_dua AS (
    SELECT raceId, driverId, MIN(constructorId) AS constructorId
    FROM F1_SOURCE.dbo.results
    GROUP BY raceId, driverId
)
INSERT INTO FactPitStop (DateKey, RaceKey, CircuitKey, DriverKey, ConstructorKey, StopNumber, LapNumber, DurationMs)
SELECT  YEAR(ra.[date]) * 10000 + MONTH(ra.[date]) * 100 + DAY(ra.[date]),
        dr.RaceKey, dc.CircuitKey, dd.DriverKey, dk.ConstructorKey,
        p.[stop], p.lap, p.milliseconds
FROM F1_SOURCE.dbo.pit_stops p
JOIN F1_SOURCE.dbo.races ra ON ra.raceId        = p.raceId
JOIN doi_cua_tay_dua     t  ON t.raceId         = p.raceId AND t.driverId = p.driverId
JOIN DimRace         dr     ON dr.RaceID        = p.raceId
JOIN DimCircuit      dc     ON dc.CircuitID     = ra.circuitId
JOIN DimDriver       dd     ON dd.DriverID      = p.driverId
JOIN DimConstructor  dk     ON dk.ConstructorID = t.constructorId;
PRINT N'Đã nạp FactPitStop';

-- 2.5 FactDriverStanding: từ bảng driver_standings
INSERT INTO FactDriverStanding (DateKey, RaceKey, DriverKey, StandingPosition, TotalPoints, TotalWins)
SELECT  YEAR(ra.[date]) * 10000 + MONTH(ra.[date]) * 100 + DAY(ra.[date]),
        dr.RaceKey, dd.DriverKey,
        s.position, s.points, s.wins
FROM F1_SOURCE.dbo.driver_standings s
JOIN F1_SOURCE.dbo.races ra ON ra.raceId   = s.raceId
JOIN DimRace         dr     ON dr.RaceID   = s.raceId
JOIN DimDriver       dd     ON dd.DriverID = s.driverId;
PRINT N'Đã nạp FactDriverStanding';
GO

/* =====================================================================
   PHẦN 3. KIỂM TRA: số dòng mỗi bảng phải khớp cột "SoDongMongDoi"
   ===================================================================== */
SELECT TenBang, SoDong, SoDongMongDoi,
       CASE WHEN SoDong = SoDongMongDoi THEN N'Đúng' ELSE N'SAI – kiểm tra lại' END AS KetQua
FROM (
    SELECT N'DimDate' AS TenBang,        (SELECT COUNT(*) FROM DimDate)            AS SoDong, 27394  AS SoDongMongDoi UNION ALL
    SELECT N'DimRace',                   (SELECT COUNT(*) FROM DimRace),                      1125   UNION ALL
    SELECT N'DimCircuit',                (SELECT COUNT(*) FROM DimCircuit),                   77     UNION ALL
    SELECT N'DimDriver',                 (SELECT COUNT(*) FROM DimDriver),                    861    UNION ALL
    SELECT N'DimConstructor',            (SELECT COUNT(*) FROM DimConstructor),               212    UNION ALL
    SELECT N'DimStatus',                 (SELECT COUNT(*) FROM DimStatus),                    139    UNION ALL
    SELECT N'FactRaceResult',            (SELECT COUNT(*) FROM FactRaceResult),               26759  UNION ALL
    SELECT N'FactQualifying',            (SELECT COUNT(*) FROM FactQualifying),               10494  UNION ALL
    SELECT N'FactLapTime',               (SELECT COUNT(*) FROM FactLapTime),                  589081 UNION ALL
    SELECT N'FactPitStop',               (SELECT COUNT(*) FROM FactPitStop),                  11371  UNION ALL
    SELECT N'FactDriverStanding',        (SELECT COUNT(*) FROM FactDriverStanding),           34863
) x;
