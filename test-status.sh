#!/bin/bash

# Test Status Check Script

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}PlugFest 2025 - Local Test Status${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check ports
echo -e "${YELLOW}[1] Checking Service Ports...${NC}"
for port in 8080 8081 8082 3000; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Port $port is listening"
    else
        echo -e "  ${RED}✗${NC} Port $port is NOT listening"
    fi
done
echo ""

# Check Redis
echo -e "${YELLOW}[2] Checking Redis...${NC}"
if redis-cli ping > /dev/null 2>&1; then
    STREAM_LEN=$(redis-cli XLEN traffic-stream 2>/dev/null || echo "0")
    echo -e "  ${GREEN}✓${NC} Redis is running"
    echo -e "  ${BLUE}ℹ${NC} Stream length: $STREAM_LEN messages"
else
    echo -e "  ${RED}✗${NC} Redis is NOT running"
fi
echo ""

# Check MariaDB
echo -e "${YELLOW}[3] Checking MariaDB...${NC}"
ACCIDENT_COUNT=$(mysql -u suslmk -pmaster pf2005 -sN -e "SELECT COUNT(*) FROM accidents;" 2>/dev/null || echo "ERROR")
if [ "$ACCIDENT_COUNT" != "ERROR" ]; then
    echo -e "  ${GREEN}✓${NC} MariaDB is running"
    echo -e "  ${BLUE}ℹ${NC} Total accidents: $ACCIDENT_COUNT"

    RECENT=$(mysql -u suslmk -pmaster pf2005 -sN -e "SELECT acc_type, acc_point_nm FROM accidents ORDER BY created_at DESC LIMIT 1;" 2>/dev/null)
    echo -e "  ${BLUE}ℹ${NC} Latest: $RECENT"
else
    echo -e "  ${RED}✗${NC} MariaDB is NOT accessible"
fi
echo ""

# Check API endpoints
echo -e "${YELLOW}[4] Checking API Endpoints...${NC}"

# Simulator
if curl -s -f http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Traffic Simulator (8080)"
else
    if curl -s -f http://localhost:8080/api/traffic > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Traffic Simulator (8080)"
    else
        echo -e "  ${RED}✗${NC} Traffic Simulator (8080)"
    fi
fi

# Data API
if curl -s -f http://localhost:8081/health > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Data API Service (8081)"
else
    echo -e "  ${RED}✗${NC} Data API Service (8081)"
fi

# Gateway
if curl -s -f http://localhost:8082/health > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} API Gateway (8082)"
else
    echo -e "  ${RED}✗${NC} API Gateway (8082)"
fi

# Frontend
if curl -s -f http://localhost:3000 > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Frontend (3000)"
else
    echo -e "  ${RED}✗${NC} Frontend (3000)"
fi
echo ""

# Get statistics
echo -e "${YELLOW}[5] Current Statistics...${NC}"
STATS=$(curl -s http://localhost:8081/api/accidents/stats 2>/dev/null)
if [ ! -z "$STATS" ]; then
    echo "$STATS" | jq -r '
        "  Total Accidents: \(.totalAccidents)",
        "  Today Accidents: \(.todayAccidents)",
        "  By Type:",
        (.byType | to_entries[] | "    - \(.key): \(.value)")
    ' 2>/dev/null || echo "$STATS"
else
    echo -e "  ${RED}✗${NC} Cannot fetch statistics"
fi
echo ""

# Recent logs
echo -e "${YELLOW}[6] Recent Activity...${NC}"
if [ -f collector.log ]; then
    echo -e "  ${BLUE}Collector:${NC}"
    tail -2 collector.log | sed 's/^/    /'
fi

if [ -f processor.log ]; then
    echo -e "  ${BLUE}Processor:${NC}"
    tail -2 processor.log | sed 's/^/    /'
fi
echo ""

echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}Access the dashboard: http://localhost:3000${NC}"
echo -e "${BLUE}================================================${NC}"
