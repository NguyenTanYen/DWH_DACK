/* =====================================================================
   DEMO SCD TYPE 1 / TYPE 2 VÀ NẠP TĂNG DẦN (để trình bày với giảng viên)
   Chạy SAU khi 03_etl_f1_dwh.sql đã chạy xong. Chạy từng khối (bôi đen + F5).
   ===================================================================== */

/* ---- Khối 1: trạng thái ban đầu – mỗi tay đua 1 dòng ---- */
SELECT DriverKey, DriverID, FullName, DriverCode, Nationality,
       RowEffectiveDate, RowExpirationDate, IsCurrentRow
FROM F1_DWH.dbo.DimDriver
WHERE DriverRef = N'hamilton';

/* ---- Khối 2: giả lập thay đổi ở hệ thống nguồn ----
   - forename  : thuộc tính Type 1  → ghi đè, không giữ lịch sử
   - code      : thuộc tính Type 2  → tạo phiên bản mới                   */
UPDATE F1_SOURCE.dbo.drivers SET forename = N'Sir Lewis' WHERE driverRef = N'hamilton';
UPDATE F1_SOURCE.dbo.drivers SET code     = N'LHM'       WHERE driverRef = N'hamilton';

/* ---- Khối 3: chạy lại ETL ---- */
EXEC F1_DWH.etl.usp_Run_ETL;
-- Kết quả mong đợi: các fact giao dịch thêm 0 dòng (nạp tăng dần, không trùng),
-- DimAudit có thêm 1 lô mới.

/* ---- Khối 4: kiểm tra – Hamilton giờ có 2 dòng ----
   Dòng cũ: code HAM, Expired, hết hiệu lực hôm qua
   Dòng mới: code LHM, Current, hiệu lực từ hôm nay
   Cả 2 dòng đều có FirstName = 'Sir Lewis' (Type 1 ghi đè mọi phiên bản)  */
SELECT DriverKey, DriverID, FullName, DriverCode, Nationality,
       RowEffectiveDate, RowExpirationDate, IsCurrentRow
FROM F1_DWH.dbo.DimDriver
WHERE DriverRef = N'hamilton'
ORDER BY RowEffectiveDate;

/* ---- Khối 5: fact lịch sử vẫn trỏ về phiên bản cũ (đúng tinh thần SCD2) ---- */
SELECT d.DriverKey, d.DriverCode, d.IsCurrentRow, COUNT(*) AS RaceEntries
FROM F1_DWH.dbo.FactRaceResult f
JOIN F1_DWH.dbo.DimDriver d ON d.DriverKey = f.DriverKey
WHERE d.DriverRef = N'hamilton'
GROUP BY d.DriverKey, d.DriverCode, d.IsCurrentRow;

/* ---- Khối 6: lịch sử các lần chạy ETL (audit dimension) ---- */
SELECT * FROM F1_DWH.dbo.DimAudit ORDER BY AuditKey;

/* ---- Khối 7 (tuỳ chọn): hoàn tác dữ liệu nguồn ----
   Lưu ý: hoàn tác nguồn rồi chạy ETL sẽ tạo thêm phiên bản thứ 3 (HAM).
   Muốn kho sạch như ban đầu: chạy lại 01_create_f1_dwh.sql rồi 03_etl_f1_dwh.sql. */
UPDATE F1_SOURCE.dbo.drivers SET forename = N'Lewis', code = N'HAM' WHERE driverRef = N'hamilton';
