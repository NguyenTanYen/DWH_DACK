"""
ETL cho Kho dữ liệu Formula 1 (F1_DWH)
======================================
Đọc 14 file CSV gốc (Ergast F1 dataset 1950-2024) -> làm sạch -> sinh
7 bảng chiều + 6 bảng sự kiện theo lược đồ chòm sao (fact constellation).

Cách dùng (nhanh nhất): bấm đúp file run_etl.bat.

Hoặc chạy tay:
    pip install pandas pyodbc
    python etl_f1_dwh.py --src "D:/1. DWH/DACK/DATASET/archive" --out star ^
        --server ".\\SQLEXPRESS" --create 01_create_f1_dwh.sql

    --server  : tên SQL Server như trong SSMS (Windows Authentication)
    --create  : chạy file DDL trước (tạo lại database F1_DWH + 13 bảng, xoá dữ liệu cũ)
    --sqlite  : (tuỳ chọn) nạp vào file SQLite để thử
"""
import argparse
import os
import re

import numpy as np
import pandas as pd

NA = ["\\N", ""]

# ---------------------------------------------------------------------------
# Bảng tra cứu phục vụ làm giàu dữ liệu (enrichment)
# ---------------------------------------------------------------------------
COUNTRY_FIX = {"United States": "USA"}  # dữ liệu gốc ghi lẫn 2 kiểu

CONTINENT = {
    "Argentina": "South America", "Brazil": "South America", "Mexico": "North America",
    "USA": "North America", "Canada": "North America",
    "Australia": "Oceania",
    "Bahrain": "Asia", "China": "Asia", "India": "Asia", "Japan": "Asia", "Korea": "Asia",
    "Malaysia": "Asia", "Qatar": "Asia", "Saudi Arabia": "Asia", "Singapore": "Asia",
    "UAE": "Asia", "Azerbaijan": "Asia", "Turkey": "Europe", "Russia": "Europe",
    "Morocco": "Africa", "South Africa": "Africa",
}  # còn lại mặc định Europe

# quốc tịch -> quốc gia (khớp với cột country của circuits) để xác định "chặng đua sân nhà"
NATIONALITY_COUNTRY = {
    "American": "USA", "American-Italian": "USA", "Argentine": "Argentina",
    "Argentine-Italian": "Argentina", "Argentinian": "Argentina", "Australian": "Australia",
    "Austrian": "Austria", "Belgian": "Belgium", "Brazilian": "Brazil", "British": "UK",
    "Canadian": "Canada", "Chilean": "Chile", "Chinese": "China", "Colombian": "Colombia",
    "Czech": "Czech Republic", "Danish": "Denmark", "Dutch": "Netherlands",
    "East German": "Germany", "Finnish": "Finland", "French": "France", "German": "Germany",
    "Hong Kong": "Hong Kong", "Hungarian": "Hungary", "Indian": "India",
    "Indonesian": "Indonesia", "Irish": "Ireland", "Italian": "Italy", "Japanese": "Japan",
    "Liechtensteiner": "Liechtenstein", "Malaysian": "Malaysia", "Mexican": "Mexico",
    "Monegasque": "Monaco", "New Zealander": "New Zealand", "Polish": "Poland",
    "Portuguese": "Portugal", "Rhodesian": "Rhodesia", "Russian": "Russia",
    "South African": "South Africa", "Spanish": "Spain", "Swedish": "Sweden",
    "Swiss": "Switzerland", "Thai": "Thailand", "Uruguayan": "Uruguay",
    "Venezuelan": "Venezuela",
}

MECHANICAL_KW = [
    "engine", "gearbox", "transmission", "clutch", "hydraulics", "electrical", "radiator",
    "suspension", "brake", "differential", "overheating", "mechanical", "driveshaft",
    "fuel", "water", "wheel", "throttle", "steering", "technical", "electronics",
    "exhaust", "oil", "pneumatics", "power", "drivetrain", "ignition", "chassis",
    "battery", "halfshaft", "crankshaft", "alternator", "injection", "distributor",
    "turbo", "cv joint", "axle", "magneto", "supercharger", "ers", "cooling", "vibrations",
    "spark", "launch control", "heat shield", "undertray", "handling", "seat", "safety belt",
    "tyre", "puncture", "track rod", "stalled", "front wing", "rear wing", "broken wing", "brake duct",
]


def status_group(s: str) -> str:
    sl = s.lower()
    if s == "Finished":
        return "Finished"
    if re.match(r"^\+\d+ Laps?$", s):
        return "Finished (lapped)"
    if sl in ("disqualified", "excluded", "underweight"):
        return "Disqualified"
    if sl in ("did not qualify", "did not prequalify", "107% rule", "withdrew",
              "not restarted", "not classified"):
        return "Did not start / Not classified"
    if any(k in sl for k in ("accident", "collision", "spun off", "damage", "debris", "fire")) \
            and "heat shield" not in sl and "engine fire" not in sl:
        return "Accident / Collision"
    if any(k in sl for k in ("injur", "illness", "unwell", "physical", "eye", "fatal")):
        return "Driver health"
    if any(k in sl for k in MECHANICAL_KW):
        return "Mechanical / Technical"
    return "Other"


def lap_to_ms(t):
    """'1:27.452' -> 87452 ; '58.123' -> 58123 ; NaN -> NaN"""
    if pd.isna(t):
        return np.nan
    t = str(t).strip()
    try:
        if ":" in t:
            m, s = t.split(":")
            return int(round((int(m) * 60 + float(s)) * 1000))
        return int(round(float(t) * 1000))
    except ValueError:
        return np.nan


def read(src, name):
    return pd.read_csv(os.path.join(src, f"{name}.csv"), na_values=NA, keep_default_na=False)


def date_key(s):
    return pd.to_datetime(s).dt.strftime("%Y%m%d").astype(int)


# ---------------------------------------------------------------------------
def build(src):
    circuits, constructors, drivers = read(src, "circuits"), read(src, "constructors"), read(src, "drivers")
    races, status, results = read(src, "races"), read(src, "status"), read(src, "results")
    sprint, quali = read(src, "sprint_results"), read(src, "qualifying")
    laps, pits = read(src, "lap_times"), read(src, "pit_stops")
    dstand, cstand = read(src, "driver_standings"), read(src, "constructor_standings")

    T = {}

    # ---------------- DimDate ----------------
    rd = pd.to_datetime(races["date"])
    dates = pd.DataFrame({"FullDate": pd.date_range(f"{rd.min().year}-01-01", f"{rd.max().year}-12-31")})
    d = dates["FullDate"]
    dates["DateKey"] = d.dt.strftime("%Y%m%d").astype(int)
    dates["Day"] = d.dt.day
    dates["Month"] = d.dt.month
    dates["MonthName"] = d.dt.month_name()
    dates["Quarter"] = d.dt.quarter
    dates["Year"] = d.dt.year
    dates["Decade"] = (d.dt.year // 10 * 10).astype(str) + "s"
    dates["DayOfWeek"] = d.dt.dayofweek + 1  # 1 = Monday
    dates["DayName"] = d.dt.day_name()
    dates["IsWeekend"] = (d.dt.dayofweek >= 5).astype(int)
    dates["FullDate"] = d.dt.date
    T["DimDate"] = dates[["DateKey", "FullDate", "Day", "Month", "MonthName", "Quarter",
                          "Year", "Decade", "DayOfWeek", "DayName", "IsWeekend"]]

    # ---------------- DimCircuit ----------------
    c = circuits.copy()
    c["country"] = c["country"].replace(COUNTRY_FIX)
    c["Continent"] = c["country"].map(CONTINENT).fillna("Europe")
    c["CircuitKey"] = range(1, len(c) + 1)
    T["DimCircuit"] = c.rename(columns={
        "circuitId": "CircuitID", "circuitRef": "CircuitRef", "name": "CircuitName",
        "location": "City", "country": "Country", "lat": "Latitude", "lng": "Longitude",
        "alt": "Altitude"})[["CircuitKey", "CircuitID", "CircuitRef", "CircuitName", "City",
                             "Country", "Continent", "Latitude", "Longitude", "Altitude"]]
    ck = dict(zip(c.circuitId, c.CircuitKey))

    # ---------------- DimRace ----------------
    r = races.sort_values(["year", "round"]).copy()
    r["RaceKey"] = range(1, len(r) + 1)
    r["RoundsInSeason"] = r.groupby("year")["round"].transform("max")
    r["IsSeasonFinale"] = (r["round"] == r["RoundsInSeason"]).astype(int)
    r["HasSprint"] = r["sprint_date"].notna().astype(int) | r["raceId"].isin(sprint.raceId).astype(int)
    r["Decade"] = (r["year"] // 10 * 10).astype(str) + "s"
    r["DateKey"] = date_key(r["date"])
    T["DimRace"] = r.rename(columns={
        "raceId": "RaceID", "year": "Season", "round": "Round", "name": "RaceName",
        "date": "RaceDate", "time": "RaceStartTimeUTC"})[[
        "RaceKey", "RaceID", "Season", "Decade", "Round", "RoundsInSeason", "IsSeasonFinale",
        "RaceName", "RaceDate", "RaceStartTimeUTC", "HasSprint"]]
    race_lu = r.set_index("raceId")[["RaceKey", "DateKey", "circuitId", "date", "year"]].copy()
    race_lu["CircuitKey"] = race_lu["circuitId"].map(ck)

    # ---------------- DimDriver ----------------
    dr = drivers.copy()
    dr["nationality"] = dr["nationality"].str.strip()
    dr["DriverKey"] = range(1, len(dr) + 1)
    dr["FullName"] = dr["forename"] + " " + dr["surname"]
    dr["NationalityCountry"] = dr["nationality"].map(NATIONALITY_COUNTRY)
    T["DimDriver"] = dr.rename(columns={
        "driverId": "DriverID", "driverRef": "DriverRef", "code": "DriverCode",
        "number": "PermanentNumber", "forename": "FirstName", "surname": "LastName",
        "dob": "DateOfBirth", "nationality": "Nationality"})[[
        "DriverKey", "DriverID", "DriverRef", "DriverCode", "PermanentNumber", "FirstName",
        "LastName", "FullName", "DateOfBirth", "Nationality", "NationalityCountry"]]
    dk = dict(zip(dr.driverId, dr.DriverKey))
    dob = dict(zip(dr.driverId, pd.to_datetime(dr.dob)))
    dnat = dict(zip(dr.driverId, dr.NationalityCountry))

    # ---------------- DimConstructor ----------------
    co = constructors.copy()
    co["nationality"] = co["nationality"].str.strip()
    co["ConstructorKey"] = range(1, len(co) + 1)
    T["DimConstructor"] = co.rename(columns={
        "constructorId": "ConstructorID", "constructorRef": "ConstructorRef",
        "name": "ConstructorName", "nationality": "Nationality"})[[
        "ConstructorKey", "ConstructorID", "ConstructorRef", "ConstructorName", "Nationality"]]
    cok = dict(zip(co.constructorId, co.ConstructorKey))

    # ---------------- DimStatus ----------------
    st = status.copy()
    st["StatusKey"] = range(1, len(st) + 1)
    st["StatusGroup"] = st["status"].map(status_group)
    st["IsClassifiedFinish"] = st["StatusGroup"].isin(["Finished", "Finished (lapped)"]).astype(int)
    T["DimStatus"] = st.rename(columns={"statusId": "StatusID", "status": "StatusDesc"})[[
        "StatusKey", "StatusID", "StatusDesc", "StatusGroup", "IsClassifiedFinish"]]
    sk = dict(zip(st.statusId, st.StatusKey))
    s_fin = dict(zip(st.statusId, st.IsClassifiedFinish))

    # ---------------- DimSessionType ----------------
    T["DimSessionType"] = pd.DataFrame({"SessionTypeKey": [1, 2],
                                        "SessionType": ["Grand Prix", "Sprint"]})

    def add_common(df, with_constructor=True):
        out = pd.DataFrame(index=df.index)
        out["DateKey"] = df["raceId"].map(race_lu["DateKey"])
        out["RaceKey"] = df["raceId"].map(race_lu["RaceKey"])
        out["CircuitKey"] = df["raceId"].map(race_lu["CircuitKey"])
        if "driverId" in df:
            out["DriverKey"] = df["driverId"].map(dk)
        if with_constructor:
            out["ConstructorKey"] = df["constructorId"].map(cok)
        return out

    # ---------------- FactResult (Grand Prix + Sprint) ----------------
    res = pd.concat([results.assign(SessionTypeKey=1),
                     sprint.assign(SessionTypeKey=2, rank=np.nan, fastestLapSpeed=np.nan)],
                    ignore_index=True)
    f = add_common(res)
    f["StatusKey"] = res["statusId"].map(sk)
    f["SessionTypeKey"] = res["SessionTypeKey"]
    f["SourceResultID"] = res["resultId"]
    f["CarNumber"] = res["number"]
    f["GridPosition"] = res["grid"]                         # 0 = xuất phát từ pit lane
    f["FinishPosition"] = res["position"]                   # NULL = không được xếp hạng
    f["PositionText"] = res["positionText"]
    f["PositionOrder"] = res["positionOrder"]
    f["Points"] = res["points"]
    f["LapsCompleted"] = res["laps"]
    f["RaceTimeMs"] = res["milliseconds"]
    f["FastestLapNumber"] = res["fastestLap"]
    f["FastestLapRank"] = res["rank"]
    f["FastestLapTimeMs"] = res["fastestLapTime"].map(lap_to_ms)
    f["FastestLapSpeedKph"] = pd.to_numeric(res["fastestLapSpeed"], errors="coerce")
    race_date = res["raceId"].map(race_lu["date"]).pipe(pd.to_datetime)
    f["DriverAgeAtRace"] = ((race_date - res["driverId"].map(dob)).dt.days / 365.25).round(1)
    f["PositionsGained"] = np.where(res["grid"] > 0, res["grid"] - res["positionOrder"], np.nan)
    f["IsWin"] = (res["position"] == 1).astype(int)
    f["IsPodium"] = (res["position"] <= 3).astype(int)
    f["IsPole"] = (res["grid"] == 1).astype(int)
    f["IsPointsFinish"] = (res["points"] > 0).astype(int)
    f["IsDNF"] = (1 - res["statusId"].map(s_fin)).astype(int)
    circ_country = res["raceId"].map(race_lu["circuitId"]).map(dict(zip(c.circuitId, c.country)))
    f["IsHomeRace"] = (res["driverId"].map(dnat) == circ_country).astype(int)
    f.insert(0, "ResultKey", range(1, len(f) + 1))
    T["FactResult"] = f

    # constructor của tay đua trong 1 chặng (dùng cho lap_times, pit_stops)
    drv_con = results.drop_duplicates(["raceId", "driverId"]).set_index(["raceId", "driverId"])["constructorId"]

    def con_of(df):
        idx = pd.MultiIndex.from_arrays([df["raceId"], df["driverId"]])
        return drv_con.reindex(idx).values

    # ---------------- FactQualifying ----------------
    q = quali.copy()
    fq = add_common(q)
    fq["QualiPosition"] = q["position"]
    for k in ("q1", "q2", "q3"):
        fq[f"{k.upper()}Ms"] = q[k].map(lap_to_ms)
    fq["BestLapMs"] = fq[["Q1Ms", "Q2Ms", "Q3Ms"]].min(axis=1)
    pole = fq.groupby(q["raceId"])["BestLapMs"].transform("min")
    fq["GapToPoleMs"] = fq["BestLapMs"] - pole
    fq["GapToPolePct"] = (fq["GapToPoleMs"] / pole * 100).round(3)
    fq["ReachedQ2"] = fq["Q2Ms"].notna().astype(int)
    fq["ReachedQ3"] = fq["Q3Ms"].notna().astype(int)
    T["FactQualifying"] = fq

    # ---------------- FactLapTime ----------------
    lp = laps.copy()
    lp["constructorId"] = con_of(lp)
    fl = add_common(lp)
    fl["LapNumber"] = lp["lap"]
    fl["PositionOnLap"] = lp["position"]
    fl["LapTimeMs"] = lp["milliseconds"]
    T["FactLapTime"] = fl

    # ---------------- FactPitStop ----------------
    p = pits.copy()
    p["constructorId"] = con_of(p)
    fp = add_common(p)
    fp["StopNumber"] = p["stop"]
    fp["LapNumber"] = p["lap"]
    fp["StopTimeOfDay"] = p["time"]
    fp["DurationMs"] = p["milliseconds"]
    fp["IsOutlier"] = (p["milliseconds"] > 60000).astype(int)  # cờ đỏ / sửa xe lâu
    T["FactPitStop"] = fp

    # ---------------- FactDriverStanding (snapshot sau mỗi chặng) ----------------
    ds = dstand.copy()
    fds = add_common(ds, with_constructor=False).drop(columns="CircuitKey")
    fds["StandingPosition"] = ds["position"]
    fds["CumulativePoints"] = ds["points"]
    fds["CumulativeWins"] = ds["wins"]
    fds["IsFinalStanding"] = ds["raceId"].map(r.set_index("raceId")["IsSeasonFinale"]).astype(int)
    T["FactDriverStanding"] = fds

    # ---------------- FactConstructorStanding ----------------
    cs = cstand.copy()
    fcs = add_common(cs).drop(columns="CircuitKey")
    fcs["StandingPosition"] = cs["position"]
    fcs["CumulativePoints"] = cs["points"]
    fcs["CumulativeWins"] = cs["wins"]
    fcs["IsFinalStanding"] = cs["raceId"].map(r.set_index("raceId")["IsSeasonFinale"]).astype(int)
    T["FactConstructorStanding"] = fcs

    # ép kiểu khoá ngoại về Int64 (cho phép NULL)
    for name, df in T.items():
        for col in df.columns:
            if col.endswith("Key") or col in ("GridPosition", "FinishPosition", "CarNumber",
                                               "FastestLapNumber", "FastestLapRank", "RaceTimeMs",
                                               "FastestLapTimeMs", "Q1Ms", "Q2Ms", "Q3Ms",
                                               "BestLapMs", "GapToPoleMs", "PositionsGained",
                                               "PermanentNumber", "Altitude", "DurationMs"):
                df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int64")
    return T


ORDER = ["DimDate", "DimCircuit", "DimRace", "DimDriver", "DimConstructor", "DimStatus",
         "DimSessionType", "FactResult", "FactQualifying", "FactLapTime", "FactPitStop",
         "FactDriverStanding", "FactConstructorStanding"]


def mssql_connect(server, database):
    import pyodbc
    drivers = [d for d in pyodbc.drivers() if re.match(r"ODBC Driver \d+ for SQL Server", d)]
    drivers.sort(key=lambda d: int(re.search(r"\d+", d).group()))
    driver = drivers[-1] if drivers else "SQL Server"
    cs = (f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};"
          "Trusted_Connection=yes;TrustServerCertificate=yes;")
    print(f"Kết nối {server}/{database} bằng driver '{driver}'")
    return pyodbc.connect(cs, autocommit=True)


def run_sql_file(server, path):
    """Chạy file .sql (tách theo dòng GO) – dùng để tạo database + bảng."""
    con = mssql_connect(server, "master")
    cur = con.cursor()
    with open(path, encoding="utf-8") as fh:
        batches = re.split(r"^\s*GO\s*$", fh.read(), flags=re.M | re.I)
    for b in batches:
        if b.strip():
            cur.execute(b)
    con.close()
    print("Đã tạo database F1_DWH và 13 bảng")


def load_mssql(server, T):
    con = mssql_connect(server, "F1_DWH")
    cur = con.cursor()
    cur.fast_executemany = True
    for n in ORDER:
        df = T[n]
        cols = ", ".join(f"[{c}]" for c in df.columns)
        qs = ", ".join("?" * len(df.columns))
        sql = f"INSERT INTO dbo.{n} ({cols}) VALUES ({qs})"
        obj = df.astype(object).where(df.notna(), None)
        rows = [tuple(v.item() if isinstance(v, np.generic) else v for v in r)
                for r in obj.itertuples(index=False, name=None)]
        con.autocommit = False
        for i in range(0, len(rows), 20000):
            cur.executemany(sql, rows[i:i + 20000])
        con.commit()
        con.autocommit = True
        print(f"  nạp {n:26s} {len(rows):>8,d} dòng")
    con.close()
    print("HOÀN TẤT: dữ liệu đã nằm trong database F1_DWH")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="thư mục chứa 14 file CSV gốc")
    ap.add_argument("--out", default="star", help="thư mục ghi các bảng chiều/sự kiện (CSV)")
    ap.add_argument("--server", help=r"tên SQL Server, vd .\SQLEXPRESS (Windows Authentication)")
    ap.add_argument("--create", help="file DDL chạy trước khi nạp, vd 01_create_f1_dwh.sql")
    ap.add_argument("--sqlite", help="đường dẫn file SQLite để nạp thử")
    a = ap.parse_args()

    T = build(a.src)
    os.makedirs(a.out, exist_ok=True)
    for name, df in T.items():
        df.to_csv(os.path.join(a.out, f"{name}.csv"), index=False)
        print(f"{name:26s} {len(df):>8,d} dòng")

    if a.sqlite:
        import sqlite3
        con = sqlite3.connect(a.sqlite)
        for n in ORDER:
            T[n].to_sql(n, con, if_exists="replace", index=False)
        con.close()
        print("Đã nạp vào", a.sqlite)
    if a.server:
        if a.create:
            run_sql_file(a.server, a.create)
        load_mssql(a.server, T)


if __name__ == "__main__":
    main()
