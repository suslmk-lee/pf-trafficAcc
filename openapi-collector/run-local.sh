#!/bin/bash

# OpenAPI Collector - Local Execution Script
# This script runs the openapi-collector locally to collect data from external APIs
# and populate the cache tables in the database.

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenAPI Collector - Local Runner${NC}"
echo -e "${GREEN}========================================${NC}"

# Configuration
DB_HOST="${DB_HOST:-103.218.158.244}"
DB_PORT="${DB_PORT:-30306}"
DB_USER="${DB_USER:-trafficuser}"
DB_PASSWORD="${DB_PASSWORD:-trafficpass}"
DB_NAME="${DB_NAME:-trafficdb}"

ACCIDENT_API_URL="${ACCIDENT_API_URL:-https://data.ex.co.kr/openapi/burstInfo/realTimeSms}"
ACCIDENT_API_KEY="${ACCIDENT_API_KEY:-8771969304}"
TOLLGATE_API_URL="${TOLLGATE_API_URL:-https://data.ex.co.kr/openapi/trafficapi/trafficIc}"
TOLLGATE_API_KEY="${TOLLGATE_API_KEY:-8771969304}"
ROAD_STATUS_API_URL="${ROAD_STATUS_API_URL:-https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime}"
ROAD_STATUS_API_KEY="${ROAD_STATUS_API_KEY:-8771969304}"

# Collection intervals (default: 5min for accidents/road, 15min for tollgate)
ACCIDENT_COLLECT_INTERVAL="${ACCIDENT_COLLECT_INTERVAL:-5m}"
TOLLGATE_COLLECT_INTERVAL="${TOLLGATE_COLLECT_INTERVAL:-15m}"
ROAD_STATUS_COLLECT_INTERVAL="${ROAD_STATUS_COLLECT_INTERVAL:-5m}"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Database: ${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "  User: ${DB_USER}"
echo ""
echo "  Accident API: ${ACCIDENT_API_URL}"
echo "  Accident Interval: ${ACCIDENT_COLLECT_INTERVAL}"
echo ""
echo "  Tollgate API: ${TOLLGATE_API_URL}"
echo "  Tollgate Interval: ${TOLLGATE_COLLECT_INTERVAL}"
echo ""
echo "  Road Status API: ${ROAD_STATUS_API_URL}"
echo "  Road Status Interval: ${ROAD_STATUS_COLLECT_INTERVAL}"
echo ""

# Test database connection
echo -e "${YELLOW}Testing database connection...${NC}"
if mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} --skip-ssl ${DB_NAME} -e "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Failed to connect to database${NC}"
    echo -e "${RED}Please check your database configuration${NC}"
    exit 1
fi

# Check if required cache tables exist
echo -e "${YELLOW}Checking cache tables...${NC}"
TABLES=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} --skip-ssl ${DB_NAME} -e "SHOW TABLES LIKE '%cache%';" -s -N)

if echo "$TABLES" | grep -q "traffic_accidents_cache"; then
    echo -e "${GREEN}✓ traffic_accidents_cache exists${NC}"
else
    echo -e "${RED}✗ traffic_accidents_cache not found${NC}"
    echo -e "${YELLOW}Run: mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} --skip-ssl ${DB_NAME} < ../db/add-cache-tables.sql${NC}"
    exit 1
fi

if echo "$TABLES" | grep -q "tollgate_traffic_cache"; then
    echo -e "${GREEN}✓ tollgate_traffic_cache exists${NC}"
else
    echo -e "${RED}✗ tollgate_traffic_cache not found${NC}"
    exit 1
fi

if echo "$TABLES" | grep -q "road_traffic_status_cache"; then
    echo -e "${GREEN}✓ road_traffic_status_cache exists${NC}"
else
    echo -e "${RED}✗ road_traffic_status_cache not found${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}All prerequisites met. Starting collector...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Export environment variables
export DB_HOST
export DB_PORT
export DB_USER
export DB_PASSWORD
export DB_NAME
export ACCIDENT_API_URL
export ACCIDENT_API_KEY
export TOLLGATE_API_URL
export TOLLGATE_API_KEY
export ROAD_STATUS_API_URL
export ROAD_STATUS_API_KEY
export ACCIDENT_COLLECT_INTERVAL
export TOLLGATE_COLLECT_INTERVAL
export ROAD_STATUS_COLLECT_INTERVAL

# Run the collector
go run main.go
