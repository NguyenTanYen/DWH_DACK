/* =====================================================================
   F1_DWH – Truy vấn phân tích mẫu (T-SQL)
   Minh hoạ các phép OLAP: roll-up, drill-down, slice, dice, pivot
   ===================================================================== */
USE F1_DWH;
GO

/* Q1. Top 10 tay đua nhiều chiến thắng nhất mọi thời đại (roll-up toàn bộ thời gian) */
SELECT TOP 10 d.FullName, SUM(CAST(f.IsWin AS INT)) AS Wins,
       SUM(CAST(f.IsPodium AS INT)) AS Podiums, SUM(f.Points) AS Points
FROM FactResult f JOIN DimDriver d ON d.DriverKey = f.DriverKey
WHERE f.SessionTypeKey = 1
GROUP BY d.FullName
ORDER BY Wins DESC;

/* Q2. Nhà vô địch từng mùa (dùng snapshot cuối mùa) */
SELECT r.Season, d.FullName AS Champion, s.CumulativePoints, s.CumulativeWins
FROM FactDriverStanding s
JOIN DimRace r   ON r.RaceKey = s.RaceKey
JOIN DimDriver d ON d.DriverKey = s.DriverKey
WHERE s.IsFinalStanding = 1 AND s.StandingPosition = 1
ORDER BY r.Season DESC;

/* Q3. Tỉ lệ bỏ cuộc (DNF) theo thập kỷ và nhóm nguyên nhân (drill-down Decade → StatusGroup) */
SELECT r.Decade, st.StatusGroup, COUNT(*) AS Entries,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY r.Decade) AS DECIMAL(5,1)) AS PctOfDecade
FROM FactResult f
JOIN DimRace r    ON r.RaceKey = f.RaceKey
JOIN DimStatus st ON st.StatusKey = f.StatusKey
WHERE f.SessionTypeKey = 1
GROUP BY r.Decade, st.StatusGroup
ORDER BY r.Decade, Entries DESC;

/* Q4. Đội nào pit stop nhanh nhất mỗi mùa? (loại ngoại lai > 60 s) */
WITH pit AS (
    SELECT r.Season, c.ConstructorName, AVG(p.DurationMs) / 1000.0 AS AvgPitSec, COUNT(*) AS Stops
    FROM FactPitStop p
    JOIN DimRace r        ON r.RaceKey = p.RaceKey
    JOIN DimConstructor c ON c.ConstructorKey = p.ConstructorKey
    WHERE p.IsOutlier = 0
    GROUP BY r.Season, c.ConstructorName
    HAVING COUNT(*) >= 20
)
SELECT * FROM (
    SELECT *, RANK() OVER (PARTITION BY Season ORDER BY AvgPitSec) AS rk FROM pit
) x WHERE rk = 1 ORDER BY Season;

/* Q5. Xuất phát pole thì xác suất thắng bao nhiêu? – theo thập kỷ */
SELECT r.Decade,
       CAST(100.0 * SUM(CAST(f.IsWin AS INT)) / COUNT(*) AS DECIMAL(5,1)) AS PoleToWinPct
FROM FactResult f JOIN DimRace r ON r.RaceKey = f.RaceKey
WHERE f.IsPole = 1 AND f.SessionTypeKey = 1
GROUP BY r.Decade ORDER BY r.Decade;

/* Q6. Lợi thế sân nhà (slice: từ 2010) */
SELECT f.IsHomeRace, AVG(f.Points) AS AvgPoints,
       CAST(100.0 * AVG(CAST(f.IsPodium AS FLOAT)) AS DECIMAL(5,2)) AS PodiumPct, COUNT(*) AS Entries
FROM FactResult f JOIN DimRace r ON r.RaceKey = f.RaceKey
WHERE f.SessionTypeKey = 1 AND r.Season >= 2010
GROUP BY f.IsHomeRace;

/* Q7. Pivot: số chiến thắng của 5 đội lớn theo châu lục (dice: Constructor × Continent) */
SELECT ConstructorName, [Europe], [Asia], [North America], [South America], [Oceania], [Africa]
FROM (
    SELECT c.ConstructorName, ci.Continent, CAST(f.IsWin AS INT) AS IsWin
    FROM FactResult f
    JOIN DimConstructor c ON c.ConstructorKey = f.ConstructorKey
    JOIN DimCircuit ci    ON ci.CircuitKey = f.CircuitKey
    WHERE f.SessionTypeKey = 1
      AND c.ConstructorName IN ('Ferrari','McLaren','Mercedes','Red Bull','Williams')
) s
PIVOT (SUM(IsWin) FOR Continent IN ([Europe],[Asia],[North America],[South America],[Oceania],[Africa])) p
ORDER BY [Europe] DESC;

/* Q8. Vòng nhanh nhất (lap record trong dữ liệu) của mỗi trường đua */
SELECT ci.CircuitName, MIN(l.LapTimeMs) / 1000.0 AS BestLapSec
FROM FactLapTime l JOIN DimCircuit ci ON ci.CircuitKey = l.CircuitKey
GROUP BY ci.CircuitName
ORDER BY ci.CircuitName;

/* Q9. Khoảng cách phân hạng tới pole trung bình của mỗi đội, mùa 2024 */
SELECT c.ConstructorName, CAST(AVG(q.GapToPolePct) AS DECIMAL(6,3)) AS AvgGapToPolePct
FROM FactQualifying q
JOIN DimRace r        ON r.RaceKey = q.RaceKey
JOIN DimConstructor c ON c.ConstructorKey = q.ConstructorKey
WHERE r.Season = 2024
GROUP BY c.ConstructorName
ORDER BY AvgGapToPolePct;

/* Q10. Diễn biến cuộc đua vô địch 2021 (snapshot theo từng chặng) */
SELECT r.[Round], r.RaceName, d.FullName, s.CumulativePoints, s.StandingPosition
FROM FactDriverStanding s
JOIN DimRace r   ON r.RaceKey = s.RaceKey
JOIN DimDriver d ON d.DriverKey = s.DriverKey
WHERE r.Season = 2021 AND d.DriverRef IN ('hamilton','max_verstappen')
ORDER BY r.[Round], d.FullName;
