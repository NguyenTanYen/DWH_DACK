/* =====================================================================
   BƯỚC 5 – CẤP QUYỀN CHO SSAS ĐỌC KHO F1_DWH
   Dịch vụ Analysis Services chạy bằng tài khoản NT Service\MSSQLServerOLAPService.
   Tài khoản này cần quyền ĐỌC kho F1_DWH để xử lý (process) khối OLAP.
   ===================================================================== */
USE master;
GO
IF SUSER_ID(N'NT Service\MSSQLServerOLAPService') IS NULL
    CREATE LOGIN [NT Service\MSSQLServerOLAPService] FROM WINDOWS;
GO
USE F1_DWH;
GO
IF USER_ID(N'NT Service\MSSQLServerOLAPService') IS NULL
    CREATE USER [NT Service\MSSQLServerOLAPService] FOR LOGIN [NT Service\MSSQLServerOLAPService];
ALTER ROLE db_datareader ADD MEMBER [NT Service\MSSQLServerOLAPService];
GO
-- Kiểm tra
SELECT dp.name AS NguoiDung, r.name AS VaiTro
FROM sys.database_role_members m
JOIN sys.database_principals dp ON dp.principal_id = m.member_principal_id
JOIN sys.database_principals r  ON r.principal_id  = m.role_principal_id
WHERE dp.name LIKE N'NT Service%';
