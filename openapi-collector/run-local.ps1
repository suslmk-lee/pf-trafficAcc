# OpenAPI Collector - Local Execution Script for Windows (PowerShell)
# This script runs the openapi-collector locally to collect data from external APIs
# and populate the cache tables in the database.

$ErrorActionPreference = "Stop"

# Color functions
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }

Write-Success "========================================"
Write-Success "OpenAPI Collector - Local Runner"
Write-Success "========================================"

# Configuration
$DB_HOST = if ($env:DB_HOST) { $env:DB_HOST } else { "103.218.158.244" }
$DB_PORT = if ($env:DB_PORT) { $env:DB_PORT } else { "30306" }
$DB_USER = if ($env:DB_USER) { $env:DB_USER } else { "trafficuser" }
$DB_PASSWORD = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { "trafficpass" }
$DB_NAME = if ($env:DB_NAME) { $env:DB_NAME } else { "trafficdb" }

$ACCIDENT_API_URL = if ($env:ACCIDENT_API_URL) { $env:ACCIDENT_API_URL } else { "https://data.ex.co.kr/openapi/burstInfo/realTimeSms" }
$ACCIDENT_API_KEY = if ($env:ACCIDENT_API_KEY) { $env:ACCIDENT_API_KEY } else { "8771969304" }
$TOLLGATE_API_URL = if ($env:TOLLGATE_API_URL) { $env:TOLLGATE_API_URL } else { "https://data.ex.co.kr/openapi/trafficapi/trafficIc" }
$TOLLGATE_API_KEY = if ($env:TOLLGATE_API_KEY) { $env:TOLLGATE_API_KEY } else { "8771969304" }
$ROAD_STATUS_API_URL = if ($env:ROAD_STATUS_API_URL) { $env:ROAD_STATUS_API_URL } else { "https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime" }
$ROAD_STATUS_API_KEY = if ($env:ROAD_STATUS_API_KEY) { $env:ROAD_STATUS_API_KEY } else { "8771969304" }

# Collection intervals (default: 5min for accidents/road, 15min for tollgate)
$ACCIDENT_COLLECT_INTERVAL = if ($env:ACCIDENT_COLLECT_INTERVAL) { $env:ACCIDENT_COLLECT_INTERVAL } else { "5m" }
$TOLLGATE_COLLECT_INTERVAL = if ($env:TOLLGATE_COLLECT_INTERVAL) { $env:TOLLGATE_COLLECT_INTERVAL } else { "15m" }
$ROAD_STATUS_COLLECT_INTERVAL = if ($env:ROAD_STATUS_COLLECT_INTERVAL) { $env:ROAD_STATUS_COLLECT_INTERVAL } else { "5m" }

Write-Info "Configuration:"
Write-Host "  Database: ${DB_HOST}:${DB_PORT}/${DB_NAME}"
Write-Host "  User: ${DB_USER}"
Write-Host ""
Write-Host "  Accident API: ${ACCIDENT_API_URL}"
Write-Host "  Accident Interval: ${ACCIDENT_COLLECT_INTERVAL}"
Write-Host ""
Write-Host "  Tollgate API: ${TOLLGATE_API_URL}"
Write-Host "  Tollgate Interval: ${TOLLGATE_COLLECT_INTERVAL}"
Write-Host ""
Write-Host "  Road Status API: ${ROAD_STATUS_API_URL}"
Write-Host "  Road Status Interval: ${ROAD_STATUS_COLLECT_INTERVAL}"
Write-Host ""

# Check if Go is installed
Write-Info "Checking Go installation..."
try {
    $goVersion = go version
    Write-Success "✓ Go is installed: $goVersion"
} catch {
    Write-Error "✗ Go is not installed or not in PATH"
    Write-Error "Please install Go from https://golang.org/dl/"
    exit 1
}

# Check if mysql client is installed (optional)
Write-Info "Checking MySQL client..."
try {
    $null = Get-Command mysql -ErrorAction Stop
    Write-Success "✓ MySQL client is installed"

    # Test database connection
    Write-Info "Testing database connection..."
    $testQuery = "SELECT 1;"
    $mysqlCmd = "mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD --skip-ssl $DB_NAME -e `"$testQuery`" 2>&1"
    $result = Invoke-Expression $mysqlCmd

    if ($LASTEXITCODE -eq 0) {
        Write-Success "✓ Database connection successful"
    } else {
        Write-Error "✗ Failed to connect to database"
        Write-Error "Please check your database configuration"
        exit 1
    }

    # Check if required cache tables exist
    Write-Info "Checking cache tables..."
    $showTablesCmd = "mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD --skip-ssl $DB_NAME -e `"SHOW TABLES LIKE '%cache%';`" -s -N 2>&1"
    $tables = Invoke-Expression $showTablesCmd

    if ($tables -match "traffic_accidents_cache") {
        Write-Success "✓ traffic_accidents_cache exists"
    } else {
        Write-Error "✗ traffic_accidents_cache not found"
        Write-Info "Run: mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD --skip-ssl $DB_NAME < ..\db\add-cache-tables.sql"
        exit 1
    }

    if ($tables -match "tollgate_traffic_cache") {
        Write-Success "✓ tollgate_traffic_cache exists"
    } else {
        Write-Error "✗ tollgate_traffic_cache not found"
        exit 1
    }

    if ($tables -match "road_traffic_status_cache") {
        Write-Success "✓ road_traffic_status_cache exists"
    } else {
        Write-Error "✗ road_traffic_status_cache not found"
        exit 1
    }
} catch {
    Write-Info "⚠ MySQL client not found - skipping database connection test"
    Write-Info "The collector will attempt to connect when it starts"
}

Write-Host ""
Write-Success "All prerequisites met. Starting collector..."
Write-Info "Press Ctrl+C to stop"
Write-Host ""

# Set environment variables
$env:DB_HOST = $DB_HOST
$env:DB_PORT = $DB_PORT
$env:DB_USER = $DB_USER
$env:DB_PASSWORD = $DB_PASSWORD
$env:DB_NAME = $DB_NAME
$env:ACCIDENT_API_URL = $ACCIDENT_API_URL
$env:ACCIDENT_API_KEY = $ACCIDENT_API_KEY
$env:TOLLGATE_API_URL = $TOLLGATE_API_URL
$env:TOLLGATE_API_KEY = $TOLLGATE_API_KEY
$env:ROAD_STATUS_API_URL = $ROAD_STATUS_API_URL
$env:ROAD_STATUS_API_KEY = $ROAD_STATUS_API_KEY
$env:ACCIDENT_COLLECT_INTERVAL = $ACCIDENT_COLLECT_INTERVAL
$env:TOLLGATE_COLLECT_INTERVAL = $TOLLGATE_COLLECT_INTERVAL
$env:ROAD_STATUS_COLLECT_INTERVAL = $ROAD_STATUS_COLLECT_INTERVAL

# Run the collector
go run main.go
