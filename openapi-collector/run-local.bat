@echo off
REM OpenAPI Collector - Local Execution Script for Windows (Batch)
REM This script runs the openapi-collector locally to collect data from external APIs
REM and populate the cache tables in the database.

setlocal enabledelayedexpansion

echo ========================================
echo OpenAPI Collector - Local Runner
echo ========================================

REM Configuration
if "%DB_HOST%"=="" set DB_HOST=103.218.158.244
if "%DB_PORT%"=="" set DB_PORT=30306
if "%DB_USER%"=="" set DB_USER=trafficuser
if "%DB_PASSWORD%"=="" set DB_PASSWORD=trafficpass
if "%DB_NAME%"=="" set DB_NAME=trafficdb

if "%ACCIDENT_API_URL%"=="" set ACCIDENT_API_URL=https://data.ex.co.kr/openapi/burstInfo/realTimeSms
if "%ACCIDENT_API_KEY%"=="" set ACCIDENT_API_KEY=8771969304
if "%TOLLGATE_API_URL%"=="" set TOLLGATE_API_URL=https://data.ex.co.kr/openapi/trafficapi/trafficIc
if "%TOLLGATE_API_KEY%"=="" set TOLLGATE_API_KEY=8771969304
if "%ROAD_STATUS_API_URL%"=="" set ROAD_STATUS_API_URL=https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime
if "%ROAD_STATUS_API_KEY%"=="" set ROAD_STATUS_API_KEY=8771969304

REM Collection intervals (default: 5min for accidents/road, 15min for tollgate)
if "%ACCIDENT_COLLECT_INTERVAL%"=="" set ACCIDENT_COLLECT_INTERVAL=5m
if "%TOLLGATE_COLLECT_INTERVAL%"=="" set TOLLGATE_COLLECT_INTERVAL=15m
if "%ROAD_STATUS_COLLECT_INTERVAL%"=="" set ROAD_STATUS_COLLECT_INTERVAL=5m

echo.
echo Configuration:
echo   Database: %DB_HOST%:%DB_PORT%/%DB_NAME%
echo   User: %DB_USER%
echo.
echo   Accident API: %ACCIDENT_API_URL%
echo   Accident Interval: %ACCIDENT_COLLECT_INTERVAL%
echo.
echo   Tollgate API: %TOLLGATE_API_URL%
echo   Tollgate Interval: %TOLLGATE_COLLECT_INTERVAL%
echo.
echo   Road Status API: %ROAD_STATUS_API_URL%
echo   Road Status Interval: %ROAD_STATUS_COLLECT_INTERVAL%
echo.

REM Check if Go is installed
echo Checking Go installation...
go version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Go is not installed or not in PATH
    echo Please install Go from https://golang.org/dl/
    exit /b 1
)
echo [OK] Go is installed
echo.

REM Check if mysql client is installed (optional)
echo Checking MySQL client...
where mysql >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] MySQL client is installed

    REM Test database connection
    echo Testing database connection...
    mysql -h %DB_HOST% -P %DB_PORT% -u %DB_USER% -p%DB_PASSWORD% --skip-ssl %DB_NAME% -e "SELECT 1;" >nul 2>&1
    if %errorlevel% equ 0 (
        echo [OK] Database connection successful
    ) else (
        echo [ERROR] Failed to connect to database
        echo Please check your database configuration
        exit /b 1
    )

    REM Check if required cache tables exist
    echo Checking cache tables...
    mysql -h %DB_HOST% -P %DB_PORT% -u %DB_USER% -p%DB_PASSWORD% --skip-ssl %DB_NAME% -e "SHOW TABLES LIKE '%%cache%%';" -s -N > temp_tables.txt 2>&1

    findstr /i "traffic_accidents_cache" temp_tables.txt >nul
    if %errorlevel% equ 0 (
        echo [OK] traffic_accidents_cache exists
    ) else (
        echo [ERROR] traffic_accidents_cache not found
        echo Run: mysql -h %DB_HOST% -P %DB_PORT% -u %DB_USER% -p%DB_PASSWORD% --skip-ssl %DB_NAME% ^< ..\db\add-cache-tables.sql
        del temp_tables.txt
        exit /b 1
    )

    findstr /i "tollgate_traffic_cache" temp_tables.txt >nul
    if %errorlevel% equ 0 (
        echo [OK] tollgate_traffic_cache exists
    ) else (
        echo [ERROR] tollgate_traffic_cache not found
        del temp_tables.txt
        exit /b 1
    )

    findstr /i "road_traffic_status_cache" temp_tables.txt >nul
    if %errorlevel% equ 0 (
        echo [OK] road_traffic_status_cache exists
    ) else (
        echo [ERROR] road_traffic_status_cache not found
        del temp_tables.txt
        exit /b 1
    )

    del temp_tables.txt
) else (
    echo [WARNING] MySQL client not found - skipping database connection test
    echo The collector will attempt to connect when it starts
)

echo.
echo All prerequisites met. Starting collector...
echo Press Ctrl+C to stop
echo.

REM Run the collector
go run main.go

endlocal
