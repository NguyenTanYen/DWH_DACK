/* =====================================================================
   KHO DỮ LIỆU FORMULA 1 (F1_DWH) – SQL Server
   Lược đồ chòm sao (Fact Constellation): 7 bảng chiều dùng chung,
   6 bảng sự kiện. Khoá thay thế (surrogate key) do ETL sinh ra.
   ===================================================================== */
IF DB_ID('F1_DWH') IS NULL CREATE DATABASE F1_DWH;
GO
USE F1_DWH;
GO

/* ---------- Xoá bảng cũ (sự kiện trước, chiều sau) ---------- */
DROP TABLE IF EXISTS dbo.FactConstructorStanding, dbo.FactDriverStanding, dbo.FactPitStop,
                     dbo.FactLapTime, dbo.FactQualifying, dbo.FactResult;
DROP TABLE IF EXISTS dbo.DimSessionType, dbo.DimStatus, dbo.DimConstructor, dbo.DimDriver,
                     dbo.DimRace, dbo.DimCircuit, dbo.DimDate;
GO

/* =========================== BẢNG CHIỀU =========================== */
CREATE TABLE dbo.DimDate (
    DateKey      INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    FullDate     DATE         NOT NULL,
    [Day]        TINYINT      NOT NULL,
    [Month]      TINYINT      NOT NULL,
    MonthName    VARCHAR(10)  NOT NULL,
    [Quarter]    TINYINT      NOT NULL,
    [Year]       SMALLINT     NOT NULL,
    Decade       VARCHAR(6)   NOT NULL,
    DayOfWeek    TINYINT      NOT NULL,               -- 1 = Monday
    DayName      VARCHAR(10)  NOT NULL,
    IsWeekend    BIT          NOT NULL
);

CREATE TABLE dbo.DimCircuit (
    CircuitKey   INT           NOT NULL PRIMARY KEY,
    CircuitID    INT           NOT NULL UNIQUE,       -- khoá tự nhiên (nguồn)
    CircuitRef   VARCHAR(50)   NOT NULL,
    CircuitName  NVARCHAR(100) NOT NULL,
    City         NVARCHAR(60)  NULL,
    Country      NVARCHAR(40)  NULL,
    Continent    VARCHAR(20)   NULL,                  -- làm giàu: Circuit → City → Country → Continent
    Latitude     DECIMAL(9,5)  NULL,
    Longitude    DECIMAL(9,5)  NULL,
    Altitude     INT           NULL
);

CREATE TABLE dbo.DimRace (
    RaceKey          INT           NOT NULL PRIMARY KEY,
    RaceID           INT           NOT NULL UNIQUE,
    Season           SMALLINT      NOT NULL,          -- phân cấp: Decade → Season → Round
    Decade           VARCHAR(6)    NOT NULL,
    [Round]          TINYINT       NOT NULL,
    RoundsInSeason   TINYINT       NOT NULL,
    IsSeasonFinale   BIT           NOT NULL,
    RaceName         NVARCHAR(100) NOT NULL,
    RaceDate         DATE          NOT NULL,
    RaceStartTimeUTC TIME          NULL,
    HasSprint        BIT           NOT NULL
);

CREATE TABLE dbo.DimDriver (
    DriverKey          INT           NOT NULL PRIMARY KEY,
    DriverID           INT           NOT NULL UNIQUE,
    DriverRef          VARCHAR(50)   NOT NULL,
    DriverCode         CHAR(3)       NULL,
    PermanentNumber    INT           NULL,
    FirstName          NVARCHAR(50)  NOT NULL,
    LastName           NVARCHAR(50)  NOT NULL,
    FullName           NVARCHAR(101) NOT NULL,
    DateOfBirth        DATE          NULL,
    Nationality        NVARCHAR(40)  NULL,
    NationalityCountry NVARCHAR(40)  NULL             -- dùng để tính IsHomeRace
);

CREATE TABLE dbo.DimConstructor (
    ConstructorKey  INT           NOT NULL PRIMARY KEY,
    ConstructorID   INT           NOT NULL UNIQUE,
    ConstructorRef  VARCHAR(50)   NOT NULL,
    ConstructorName NVARCHAR(100) NOT NULL,
    Nationality     NVARCHAR(40)  NULL
);

CREATE TABLE dbo.DimStatus (
    StatusKey          INT          NOT NULL PRIMARY KEY,
    StatusID           INT          NOT NULL UNIQUE,
    StatusDesc         VARCHAR(50)  NOT NULL,
    StatusGroup        VARCHAR(40)  NOT NULL,         -- phân cấp: Group → Status
    IsClassifiedFinish BIT          NOT NULL
);

CREATE TABLE dbo.DimSessionType (
    SessionTypeKey TINYINT     NOT NULL PRIMARY KEY,  -- 1 = Grand Prix, 2 = Sprint
    SessionType    VARCHAR(20) NOT NULL
);
GO

/* =========================== BẢNG SỰ KIỆN =========================== */
/* 1. Kết quả đua – hạt: 1 tay đua × 1 phiên đua (GP hoặc Sprint) */
CREATE TABLE dbo.FactResult (
    ResultKey          BIGINT        NOT NULL PRIMARY KEY,
    DateKey            INT           NOT NULL REFERENCES dbo.DimDate(DateKey),
    RaceKey            INT           NOT NULL REFERENCES dbo.DimRace(RaceKey),
    CircuitKey         INT           NOT NULL REFERENCES dbo.DimCircuit(CircuitKey),
    DriverKey          INT           NOT NULL REFERENCES dbo.DimDriver(DriverKey),
    ConstructorKey     INT           NOT NULL REFERENCES dbo.DimConstructor(ConstructorKey),
    StatusKey          INT           NOT NULL REFERENCES dbo.DimStatus(StatusKey),
    SessionTypeKey     TINYINT       NOT NULL REFERENCES dbo.DimSessionType(SessionTypeKey),
    SourceResultID     INT           NOT NULL,        -- degenerate dimension
    CarNumber          INT           NULL,
    GridPosition       INT           NULL,            -- 0 = xuất phát từ pit lane
    FinishPosition     INT           NULL,            -- NULL = không được xếp hạng
    PositionText       VARCHAR(5)    NULL,
    PositionOrder      INT           NOT NULL,
    Points             DECIMAL(5,2)  NOT NULL,
    LapsCompleted      INT           NOT NULL,
    RaceTimeMs         BIGINT        NULL,
    FastestLapNumber   INT           NULL,
    FastestLapRank     INT           NULL,
    FastestLapTimeMs   INT           NULL,
    FastestLapSpeedKph DECIMAL(7,3)  NULL,
    DriverAgeAtRace    DECIMAL(4,1)  NULL,
    PositionsGained    INT           NULL,            -- Grid - PositionOrder
    IsWin              BIT           NOT NULL,
    IsPodium           BIT           NOT NULL,
    IsPole             BIT           NOT NULL,
    IsPointsFinish     BIT           NOT NULL,
    IsDNF              BIT           NOT NULL,
    IsHomeRace         BIT           NOT NULL
);

/* 2. Phân hạng – hạt: 1 tay đua × 1 chặng */
CREATE TABLE dbo.FactQualifying (
    DateKey        INT           NOT NULL REFERENCES dbo.DimDate(DateKey),
    RaceKey        INT           NOT NULL REFERENCES dbo.DimRace(RaceKey),
    CircuitKey     INT           NOT NULL REFERENCES dbo.DimCircuit(CircuitKey),
    DriverKey      INT           NOT NULL REFERENCES dbo.DimDriver(DriverKey),
    ConstructorKey INT           NOT NULL REFERENCES dbo.DimConstructor(ConstructorKey),
    QualiPosition  INT           NOT NULL,
    Q1Ms           INT           NULL,
    Q2Ms           INT           NULL,
    Q3Ms           INT           NULL,
    BestLapMs      INT           NULL,
    GapToPoleMs    INT           NULL,
    GapToPolePct   DECIMAL(7,3)  NULL,
    ReachedQ2      BIT           NOT NULL,
    ReachedQ3      BIT           NOT NULL,
    CONSTRAINT PK_FactQualifying PRIMARY KEY (RaceKey, DriverKey)
);

/* 3. Thời gian vòng – hạt: 1 tay đua × 1 vòng × 1 chặng (≈ 589 nghìn dòng) */
CREATE TABLE dbo.FactLapTime (
    DateKey        INT NOT NULL REFERENCES dbo.DimDate(DateKey),
    RaceKey        INT NOT NULL REFERENCES dbo.DimRace(RaceKey),
    CircuitKey     INT NOT NULL REFERENCES dbo.DimCircuit(CircuitKey),
    DriverKey      INT NOT NULL REFERENCES dbo.DimDriver(DriverKey),
    ConstructorKey INT NULL     REFERENCES dbo.DimConstructor(ConstructorKey),
    LapNumber      INT NOT NULL,
    PositionOnLap  INT NULL,
    LapTimeMs      INT NOT NULL,
    CONSTRAINT PK_FactLapTime PRIMARY KEY (RaceKey, DriverKey, LapNumber)
);

/* 4. Pit stop – hạt: 1 lần vào pit */
CREATE TABLE dbo.FactPitStop (
    DateKey        INT         NOT NULL REFERENCES dbo.DimDate(DateKey),
    RaceKey        INT         NOT NULL REFERENCES dbo.DimRace(RaceKey),
    CircuitKey     INT         NOT NULL REFERENCES dbo.DimCircuit(CircuitKey),
    DriverKey      INT         NOT NULL REFERENCES dbo.DimDriver(DriverKey),
    ConstructorKey INT         NULL     REFERENCES dbo.DimConstructor(ConstructorKey),
    StopNumber     INT         NOT NULL,
    LapNumber      INT         NOT NULL,
    StopTimeOfDay  TIME        NULL,
    DurationMs     INT         NULL,                  -- thời gian đi qua pit lane
    IsOutlier      BIT         NOT NULL,              -- > 60 s (cờ đỏ, sửa xe...)
    CONSTRAINT PK_FactPitStop PRIMARY KEY (RaceKey, DriverKey, StopNumber)
);

/* 5. BXH tay đua – periodic snapshot sau mỗi chặng (số liệu luỹ kế, semi-additive) */
CREATE TABLE dbo.FactDriverStanding (
    DateKey          INT          NOT NULL REFERENCES dbo.DimDate(DateKey),
    RaceKey          INT          NOT NULL REFERENCES dbo.DimRace(RaceKey),
    DriverKey        INT          NOT NULL REFERENCES dbo.DimDriver(DriverKey),
    StandingPosition INT          NOT NULL,
    CumulativePoints DECIMAL(6,2) NOT NULL,
    CumulativeWins   INT          NOT NULL,
    IsFinalStanding  BIT          NOT NULL,
    CONSTRAINT PK_FactDriverStanding PRIMARY KEY (RaceKey, DriverKey)
);

/* 6. BXH đội đua – periodic snapshot sau mỗi chặng */
CREATE TABLE dbo.FactConstructorStanding (
    DateKey          INT          NOT NULL REFERENCES dbo.DimDate(DateKey),
    RaceKey          INT          NOT NULL REFERENCES dbo.DimRace(RaceKey),
    ConstructorKey   INT          NOT NULL REFERENCES dbo.DimConstructor(ConstructorKey),
    StandingPosition INT          NOT NULL,
    CumulativePoints DECIMAL(6,2) NOT NULL,
    CumulativeWins   INT          NOT NULL,
    IsFinalStanding  BIT          NOT NULL,
    CONSTRAINT PK_FactConstructorStanding PRIMARY KEY (RaceKey, ConstructorKey)
);
GO

/* ---------- Chỉ mục hỗ trợ truy vấn OLAP ---------- */
CREATE INDEX IX_FactResult_Driver      ON dbo.FactResult (DriverKey, RaceKey) INCLUDE (Points, IsWin, IsPodium);
CREATE INDEX IX_FactResult_Constructor ON dbo.FactResult (ConstructorKey, RaceKey) INCLUDE (Points, IsWin);
CREATE INDEX IX_FactLapTime_Circuit    ON dbo.FactLapTime (CircuitKey) INCLUDE (LapTimeMs);
GO
