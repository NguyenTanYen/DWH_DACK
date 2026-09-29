/* =====================================================================
   BƯỚC 2 – TẠO KHO DỮ LIỆU F1_DWH (lược đồ hình sao theo Kimball)
   ---------------------------------------------------------------------
   Kho gồm:
     6 bảng chiều  : DimDate, DimRace, DimCircuit, DimDriver,
                     DimConstructor, DimStatus
     5 bảng sự kiện: FactRaceResult, FactQualifying, FactLapTime,
                     FactPitStop, FactDriverStanding
   Chạy file này SAU file 00 (tạo CSDL nguồn F1_SOURCE).
   Chạy lại file này sẽ XOÁ kho cũ và tạo kho mới trống.
   ===================================================================== */
USE master;
GO
IF DB_ID('F1_DWH') IS NOT NULL
BEGIN
    ALTER DATABASE F1_DWH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE F1_DWH;
END
GO
CREATE DATABASE F1_DWH;
GO
USE F1_DWH;
GO
/* =====================================================================
   PHẦN 1. CÁC BẢNG CHIỀU (DIMENSION)
   - Mỗi bảng chiều có một KHOÁ THAY THẾ (…Key) do kho tự sinh (IDENTITY)
     và giữ lại MÃ GỐC của nguồn (…ID) để đối chiếu khi nạp dữ liệu.
   - Riêng DimDate dùng khoá dạng số yyyymmdd (ví dụ 20240302).
   ===================================================================== */

-- 1.1 Chiều thời gian: mỗi dòng là một ngày
CREATE TABLE DimDate (
    DateKey    INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    FullDate   DATE         NOT NULL,               -- ngày đầy đủ
    [Day]      TINYINT      NOT NULL,               -- ngày trong tháng
    [Month]    TINYINT      NOT NULL,               -- tháng
    [Quarter]  TINYINT      NOT NULL,               -- quý
    [Year]     SMALLINT     NOT NULL,               -- năm
    Decade     NVARCHAR(10) NOT NULL                -- thập kỷ, ví dụ '2020s'
);

-- 1.2 Chiều chặng đua: mỗi dòng là một chặng Grand Prix
CREATE TABLE DimRace (
    RaceKey   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RaceID    INT           NOT NULL,               -- mã chặng ở nguồn (races.raceId)
    RaceName  NVARCHAR(100) NOT NULL,               -- tên chặng
    Season    SMALLINT      NOT NULL,               -- mùa giải (năm)
    [Round]   TINYINT       NOT NULL                -- chặng thứ mấy trong mùa
);

-- 1.3 Chiều trường đua: mỗi dòng là một trường đua
CREATE TABLE DimCircuit (
    CircuitKey  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CircuitID   INT           NOT NULL,             -- mã ở nguồn (circuits.circuitId)
    CircuitName NVARCHAR(100) NOT NULL,             -- tên trường đua
    City        NVARCHAR(100) NULL,                 -- thành phố
    Country     NVARCHAR(50)  NULL                  -- quốc gia
);

-- 1.4 Chiều tay đua: mỗi dòng là một tay đua
CREATE TABLE DimDriver (
    DriverKey   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DriverID    INT           NOT NULL,             -- mã ở nguồn (drivers.driverId)
    DriverCode  NVARCHAR(3)   NULL,                 -- mã 3 chữ, ví dụ HAM
    FullName    NVARCHAR(101) NOT NULL,             -- họ tên
    DateOfBirth DATE          NULL,                 -- ngày sinh
    Nationality NVARCHAR(50)  NULL                  -- quốc tịch
);

-- 1.5 Chiều đội đua: mỗi dòng là một đội đua
CREATE TABLE DimConstructor (
    ConstructorKey  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ConstructorID   INT           NOT NULL,         -- mã ở nguồn (constructors.constructorId)
    ConstructorName NVARCHAR(100) NOT NULL,         -- tên đội
    Nationality     NVARCHAR(50)  NULL              -- quốc tịch đội
);

-- 1.6 Chiều trạng thái kết thúc cuộc đua
CREATE TABLE DimStatus (
    StatusKey   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StatusID    INT          NOT NULL,              -- mã ở nguồn (status.statusId)
    StatusName  NVARCHAR(50) NOT NULL,              -- trạng thái gốc, ví dụ 'Engine'
    StatusGroup NVARCHAR(30) NOT NULL               -- nhóm: Hoàn thành / Hoàn thành (bị bắt vòng) / Bỏ cuộc
);
GO

/* =====================================================================
   PHẦN 2. CÁC BẢNG SỰ KIỆN (FACT)
   - Mỗi bảng sự kiện gồm: các khoá ngoại trỏ tới bảng chiều + các độ đo (số).
   - HẠT (grain) của từng bảng ghi ở dòng chú thích phía trên.
   ===================================================================== */

-- 2.1 Kết quả đua. HẠT: 1 tay đua × 1 chặng Grand Prix
CREATE TABLE FactRaceResult (
    ResultID         INT          NOT NULL PRIMARY KEY,  -- mã kết quả ở nguồn (mỗi dòng một mã)
    DateKey          INT          NOT NULL REFERENCES DimDate(DateKey),
    RaceKey          INT          NOT NULL REFERENCES DimRace(RaceKey),
    CircuitKey       INT          NOT NULL REFERENCES DimCircuit(CircuitKey),
    DriverKey        INT          NOT NULL REFERENCES DimDriver(DriverKey),
    ConstructorKey   INT          NOT NULL REFERENCES DimConstructor(ConstructorKey),
    StatusKey        INT          NOT NULL REFERENCES DimStatus(StatusKey),
    GridPosition     INT          NULL,      -- vị trí xuất phát (0 = xuất phát từ làn pit)
    FinishPosition   INT          NULL,      -- vị trí về đích (NULL = không được xếp hạng)
    Points           DECIMAL(5,2) NOT NULL,  -- điểm giành được
    LapsCompleted    INT          NOT NULL,  -- số vòng đã chạy
    RaceTimeMs       BIGINT       NULL,      -- tổng thời gian đua (mili-giây)
    FastestLapTimeMs INT          NULL,      -- vòng nhanh nhất của tay đua (mili-giây)
    IsWin            TINYINT      NOT NULL,  -- 1 nếu thắng chặng
    IsPodium         TINYINT      NOT NULL,  -- 1 nếu về trong top 3
    IsFinished       TINYINT      NOT NULL   -- 1 nếu hoàn thành cuộc đua
);

-- 2.2 Phân hạng. HẠT: 1 tay đua × 1 chặng (có từ năm 1994)
CREATE TABLE FactQualifying (
    QualifyID      INT NOT NULL PRIMARY KEY,             -- mã phân hạng ở nguồn
    DateKey        INT NOT NULL REFERENCES DimDate(DateKey),
    RaceKey        INT NOT NULL REFERENCES DimRace(RaceKey),
    CircuitKey     INT NOT NULL REFERENCES DimCircuit(CircuitKey),
    DriverKey      INT NOT NULL REFERENCES DimDriver(DriverKey),
    ConstructorKey INT NOT NULL REFERENCES DimConstructor(ConstructorKey),
    QualiPosition  INT NOT NULL,             -- vị trí phân hạng
    Q1Ms           INT NULL,                 -- thời gian vòng Q1 (mili-giây)
    Q2Ms           INT NULL,                 -- thời gian vòng Q2
    Q3Ms           INT NULL,                 -- thời gian vòng Q3
    BestLapMs      INT NULL                  -- thời gian tốt nhất trong Q1, Q2, Q3
);

-- 2.3 Thời gian từng vòng. HẠT: 1 tay đua × 1 vòng × 1 chặng (có từ năm 1996)
CREATE TABLE FactLapTime (
    DateKey       INT NOT NULL REFERENCES DimDate(DateKey),
    RaceKey       INT NOT NULL REFERENCES DimRace(RaceKey),
    CircuitKey    INT NOT NULL REFERENCES DimCircuit(CircuitKey),
    DriverKey     INT NOT NULL REFERENCES DimDriver(DriverKey),
    LapNumber     INT NOT NULL,              -- vòng thứ mấy
    PositionOnLap INT NULL,                  -- vị trí của tay đua sau vòng đó
    LapTimeMs     INT NOT NULL,              -- thời gian vòng (mili-giây)
    PRIMARY KEY (RaceKey, DriverKey, LapNumber)
);

-- 2.4 Vào pit. HẠT: 1 lần vào pit (có từ năm 2011)
CREATE TABLE FactPitStop (
    DateKey        INT NOT NULL REFERENCES DimDate(DateKey),
    RaceKey        INT NOT NULL REFERENCES DimRace(RaceKey),
    CircuitKey     INT NOT NULL REFERENCES DimCircuit(CircuitKey),
    DriverKey      INT NOT NULL REFERENCES DimDriver(DriverKey),
    ConstructorKey INT NOT NULL REFERENCES DimConstructor(ConstructorKey),
    StopNumber     INT NOT NULL,             -- lần vào pit thứ mấy
    LapNumber      INT NOT NULL,             -- vào pit ở vòng nào
    DurationMs     INT NULL,                 -- thời gian đi qua làn pit (mili-giây)
    PRIMARY KEY (RaceKey, DriverKey, StopNumber)
);

-- 2.5 Bảng xếp hạng tay đua. HẠT: 1 tay đua × sau mỗi chặng
--     Đây là bảng "ảnh chụp định kỳ": điểm và số trận thắng là số LUỸ KẾ
--     tính đến chặng đó, nên KHÔNG được cộng dồn theo thời gian.
CREATE TABLE FactDriverStanding (
    DateKey        INT NOT NULL REFERENCES DimDate(DateKey),
    RaceKey        INT NOT NULL REFERENCES DimRace(RaceKey),
    DriverKey      INT NOT NULL REFERENCES DimDriver(DriverKey),
    StandingPosition INT          NOT NULL,  -- hạng hiện tại
    TotalPoints      DECIMAL(6,2) NOT NULL,  -- tổng điểm luỹ kế
    TotalWins        INT          NOT NULL,  -- tổng số trận thắng luỹ kế
    PRIMARY KEY (RaceKey, DriverKey)
);
GO

/* =====================================================================
   PHẦN 3. HÀM ĐỔI THỜI GIAN
   Nguồn ghi thời gian vòng dạng chuỗi '1:27.452' (phút:giây.phần nghìn).
   Hàm này đổi sang số mili-giây (87452) để có thể so sánh, tính trung bình.
   ===================================================================== */
CREATE FUNCTION dbo.fn_DoiThoiGianSangMs (@chuoi NVARCHAR(20))
RETURNS INT
AS
BEGIN
    RETURN CASE
        -- chuỗi rỗng → không có giá trị
        WHEN @chuoi IS NULL OR @chuoi = N'' THEN NULL
        -- chỉ có giây, ví dụ '58.123' → 58123
        WHEN CHARINDEX(N':', @chuoi) = 0
            THEN CAST(TRY_CONVERT(DECIMAL(10,3), @chuoi) * 1000 AS INT)
        -- có phút, ví dụ '1:27.452' → (1×60 + 27,452) × 1000 = 87452
        ELSE CAST( ( TRY_CONVERT(INT, LEFT(@chuoi, CHARINDEX(N':', @chuoi) - 1)) * 60
                   + TRY_CONVERT(DECIMAL(10,3), SUBSTRING(@chuoi, CHARINDEX(N':', @chuoi) + 1, 20)) )
                   * 1000 AS INT)
    END;
END;
GO

PRINT N'Đã tạo xong kho F1_DWH: 6 bảng chiều, 5 bảng sự kiện.';
