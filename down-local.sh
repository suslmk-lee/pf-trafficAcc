#!/bin/bash

# PlugFest 2025 Traffic Dashboard - Stop Local Services Script

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo ""
log_info "========================================="
log_info "Stopping PlugFest 2025 Traffic Dashboard"
log_info "========================================="
echo ""

# Stop by PID files
log_info "Stopping services by PID files..."
stopped_count=0
for pidfile in .*.pid; do
    if [ -f "$pidfile" ]; then
        service=$(basename "$pidfile" .pid | sed 's/^\.//')
        pid=$(cat "$pidfile")
        if kill -0 $pid 2>/dev/null; then
            log_info "Stopping ${service} (PID: ${pid})"
            kill $pid 2>/dev/null || kill -9 $pid 2>/dev/null || true
            stopped_count=$((stopped_count + 1))
        fi
        rm "$pidfile"
    fi
done

if [ $stopped_count -gt 0 ]; then
    log_success "Stopped $stopped_count service(s) by PID"
fi

# Kill processes by name (fallback)
log_info "Checking for remaining processes..."
process_killed=0
for process in "openapi-collector" "openapi-proxy-api" "data-collector" "data-processor" "data-api-service" "api-gateway" "traffic-simulator"; do
    if pgrep -f "$process/main.go" > /dev/null 2>&1; then
        log_warning "Found remaining $process process, killing..."
        pkill -f "$process/main.go" 2>/dev/null && process_killed=1 || true
    fi
done

# Kill frontend node processes
if pgrep -f "react-scripts start" > /dev/null 2>&1; then
    log_warning "Found remaining frontend process, killing..."
    pkill -f "react-scripts start" 2>/dev/null || true
    process_killed=1
fi

# Kill by port (final cleanup)
log_info "Checking ports..."
ports_cleaned=0
for port in 8080 8081 8082 3000; do
    if lsof -Pi :${port} -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_warning "Killing process on port ${port}"
        kill -9 $(lsof -t -i:${port}) 2>/dev/null || true
        ports_cleaned=$((ports_cleaned + 1))
    fi
done

if [ $ports_cleaned -gt 0 ]; then
    log_success "Cleaned up $ports_cleaned port(s)"
fi

# Clean up log files (optional - ask user)
if [ "$1" = "--clean-logs" ]; then
    log_info "Removing log files..."
    rm -f *.log
    log_success "Log files removed"
fi

echo ""
log_success "========================================="
log_success "All services stopped!"
log_success "========================================="
echo ""

# Show what was stopped
echo "Stopped services:"
echo "  - OpenAPI Proxy API (port 8082)"
echo "  - OpenAPI Collector"
echo "  - Data Collector"
echo "  - Data Processor"
echo "  - Data API Service (port 8081)"
echo "  - API Gateway (port 8080)"
echo "  - Frontend (port 3000)"
echo ""

if [ "$1" != "--clean-logs" ]; then
    log_info "Tip: Use '$0 --clean-logs' to remove log files"
fi

echo ""
