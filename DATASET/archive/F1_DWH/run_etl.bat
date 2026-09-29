@echo off
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
cd /d "%~dp0"
echo ============================================
echo   ETL kho du lieu F1_DWH vao .\SQLEXPRESS
echo ============================================

where python >nul 2>nul
if errorlevel 1 (
  echo [LOI] Chua cai Python. Tai tai https://www.python.org/downloads/
  echo       Khi cai, nho tick "Add python.exe to PATH".
  pause
  exit /b 1
)

echo.
echo [1/2] Cai thu vien pandas, pyodbc...
python -m pip install --quiet pandas pyodbc
if errorlevel 1 ( echo [LOI] Khong cai duoc thu vien. & pause & exit /b 1 )

echo.
echo [2/2] Tao database + nap du lieu (mat khoang 1-3 phut)...
python etl_f1_dwh.py --src "%~dp0.." --out "%~dp0star" --server ".\SQLEXPRESS" --create "%~dp001_create_f1_dwh.sql"
if errorlevel 1 ( echo. & echo [LOI] ETL that bai - chup man hinh loi gui lai nhe. & pause & exit /b 1 )

echo.
echo Xong! Mo SSMS, bam Refresh muc Databases se thay F1_DWH.
pause
