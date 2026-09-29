/* =====================================================================
   BƯỚC 4 – TRUY VẤN PHÂN TÍCH TRÊN KHO F1_DWH
   Mỗi truy vấn trả lời một câu hỏi và minh hoạ một phép OLAP.
   Bôi đen từng truy vấn rồi bấm F5 để chạy riêng.
   ===================================================================== */
USE F1_DWH;
GO

/* Q1. Top 10 tay đua nhiều chiến thắng nhất mọi thời đại
       Phép OLAP: CUỘN LÊN (roll-up) – gộp từ từng chặng lên toàn bộ lịch sử */
SELECT TOP 10 d.FullName        AS TayDua,
       SUM(f.IsWin)             AS SoLanThang,
       SUM(f.IsPodium)          AS SoLanLenBuc,
       SUM(f.Points)            AS TongDiem
FROM FactRaceResult f
JOIN DimDriver d ON d.DriverKey = f.DriverKey
GROUP BY d.FullName
ORDER BY SoLanThang DESC;

/* Q2. Nhà vô địch của mỗi mùa giải
       Lấy bảng xếp hạng tại CHẶNG CUỐI của mùa (Round lớn nhất).
       Lưu ý: TotalPoints là số luỹ kế nên KHÔNG dùng SUM. */
SELECT r.Season            AS MuaGiai,
       d.FullName          AS NhaVoDich,
       s.TotalPoints       AS TongDiem,
       s.TotalWins         AS SoLanThang
FROM FactDriverStanding s
JOIN DimRace   r ON r.RaceKey   = s.RaceKey
JOIN DimDriver d ON d.DriverKey = s.DriverKey
WHERE s.StandingPosition = 1
  AND r.[Round] = (SELECT MAX(r2.[Round]) FROM DimRace r2 WHERE r2.Season = r.Season)
ORDER BY r.Season DESC;

/* Q3. Tỉ lệ không hoàn thành cuộc đua theo thập kỷ
       Phép OLAP: KHOAN XUỐNG (drill-down) – từ thập kỷ xuống nhóm trạng thái */
SELECT t.Decade                                               AS ThapKy,
       COUNT(*)                                               AS SoLuotDua,
       SUM(CASE WHEN f.IsFinished = 0 THEN 1 ELSE 0 END)      AS SoLuotKhongHoanThanh,
       CAST(100.0 * SUM(CASE WHEN f.IsFinished = 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS TiLePhanTram
FROM FactRaceResult f
JOIN DimDate t ON t.DateKey = f.DateKey
GROUP BY t.Decade
ORDER BY t.Decade;

-- Q3b. Khoan xuống thêm một mức: thập kỷ → nhóm trạng thái → trạng thái cụ thể (thập kỷ 1980)
SELECT s.StatusGroup AS NhomTrangThai, s.StatusName AS TrangThai, COUNT(*) AS SoLuot
FROM FactRaceResult f
JOIN DimDate   t ON t.DateKey   = f.DateKey
JOIN DimStatus s ON s.StatusKey = f.StatusKey
WHERE t.Decade = N'1980s'
GROUP BY s.StatusGroup, s.StatusName
ORDER BY SoLuot DESC;

/* Q4. Tổng điểm của các đội đua trong mùa giải 2024
       Phép OLAP: CẮT LÁT (slice) – cố định chiều thời gian ở Season = 2024 */
SELECT c.ConstructorName AS DoiDua,
       SUM(f.Points)     AS TongDiem,
       SUM(f.IsWin)      AS SoLanThang
FROM FactRaceResult f
JOIN DimRace        r ON r.RaceKey        = f.RaceKey
JOIN DimConstructor c ON c.ConstructorKey = f.ConstructorKey
WHERE r.Season = 2024
GROUP BY c.ConstructorName
ORDER BY TongDiem DESC;

/* Q5. Xuất phát đầu tiên thì xác suất thắng bao nhiêu? (theo thập kỷ) */
SELECT t.Decade AS ThapKy,
       COUNT(*) AS SoLanXuatPhatDau,
       SUM(f.IsWin) AS SoLanThang,
       CAST(100.0 * SUM(f.IsWin) / COUNT(*) AS DECIMAL(5,1)) AS TiLeThangPhanTram
FROM FactRaceResult f
JOIN DimDate t ON t.DateKey = f.DateKey
WHERE f.GridPosition = 1
GROUP BY t.Decade
ORDER BY t.Decade;

/* Q6. Đội có thời gian vào pit trung bình nhanh nhất mỗi mùa (2011–2024)
       Bỏ các lần vào pit trên 60 giây (do cờ đỏ, sửa xe) để không làm lệch kết quả */
WITH pit AS (
    SELECT r.Season, c.ConstructorName,
           AVG(p.DurationMs) / 1000.0 AS GiayTrungBinh
    FROM FactPitStop p
    JOIN DimRace        r ON r.RaceKey        = p.RaceKey
    JOIN DimConstructor c ON c.ConstructorKey = p.ConstructorKey
    WHERE p.DurationMs <= 60000
    GROUP BY r.Season, c.ConstructorName
    HAVING COUNT(*) >= 20
), xep_hang AS (
    SELECT *, RANK() OVER (PARTITION BY Season ORDER BY GiayTrungBinh) AS Hang
    FROM pit
)
SELECT Season AS MuaGiai, ConstructorName AS DoiDua, CAST(GiayTrungBinh AS DECIMAL(6,2)) AS GiayTrungBinh
FROM xep_hang
WHERE Hang = 1
ORDER BY Season;

/* Q7. Vòng đua nhanh nhất từng ghi nhận ở mỗi trường đua (từ 1996)
       Dùng bảng có hạt chi tiết nhất: FactLapTime */
SELECT c.CircuitName AS TruongDua, c.Country AS QuocGia,
       CAST(MIN(l.LapTimeMs) / 1000.0 AS DECIMAL(8,3)) AS VongNhanhNhatGiay
FROM FactLapTime l
JOIN DimCircuit c ON c.CircuitKey = l.CircuitKey
GROUP BY c.CircuitName, c.Country
ORDER BY VongNhanhNhatGiay;

/* Q8. Số chiến thắng của 5 đội lớn theo từng thập kỷ
       Phép OLAP: XOAY (pivot) – đưa thập kỷ thành các cột */
SELECT DoiDua, [1950s], [1960s], [1970s], [1980s], [1990s], [2000s], [2010s], [2020s]
FROM (
    SELECT c.ConstructorName AS DoiDua, t.Decade, f.IsWin
    FROM FactRaceResult f
    JOIN DimConstructor c ON c.ConstructorKey = f.ConstructorKey
    JOIN DimDate        t ON t.DateKey        = f.DateKey
    WHERE c.ConstructorName IN (N'Ferrari', N'McLaren', N'Mercedes', N'Red Bull', N'Williams')
) nguon
PIVOT (SUM(IsWin) FOR Decade IN ([1950s], [1960s], [1970s], [1980s], [1990s], [2000s], [2010s], [2020s])) bang_xoay
ORDER BY DoiDua;
