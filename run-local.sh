#!/bin/bash

# PlugFest 2025 Traffic Dashboard - Local Development Script

set -e

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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to run a Go service
run_service() {
    local service_name=$1
    local service_dir=$2
    local port=$3

    log_info "Starting ${service_name}..."
    cd ${service_dir}

    # Kill existing process on port if any
    if [ "$port" != "0" ] && lsof -Pi :${port} -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        log_warning "Killing existing process on port ${port}"
        kill -9 $(lsof -t -i:${port}) 2>/dev/null || true
        sleep 1
    fi

    # Load .env file if exists
    if [ -f .env ]; then
        export $(cat .env | grep -v '^#' | xargs)
        log_info "Loaded .env from ${service_dir}"
    fi

    go run main.go > ../${service_name}.log 2>&1 &
    local pid=$!
    echo ${pid} > ../.${service_name}.pid
    cd ..

    sleep 2
    if kill -0 ${pid} 2>/dev/null; then
        log_success "${service_name} started (PID: ${pid})"
        if [ "$port" != "0" ]; then
            log_info "  → Running on port ${port}"
        fi
    else
        log_error "${service_name} failed to start (check ${service_name}.log)"
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check MariaDB
    if ! command -v mysql &> /dev/null; then
        log_error "mysql client not found. Please install MariaDB."
        exit 1
    fi

    if ! mysql -h localhost -P 3306 -u trafficuser -ptrafficpass -e "SELECT 1" &> /dev/null; then
        log_error "Cannot connect to MariaDB. Please check:"
        log_error "  - MariaDB is running: brew services list | grep mariadb"
        log_error "  - User exists: mysql -u root -p -e \"SELECT user FROM mysql.user WHERE user='trafficuser'\""
        exit 1
    fi
    log_success "MariaDB connection OK"

    # Check Redis
    if ! command -v redis-cli &> /dev/null; then
        log_error "redis-cli not found. Please install Redis."
        exit 1
    fi

    if ! redis-cli ping &> /dev/null; then
        log_error "Cannot connect to Redis. Please check:"
        log_error "  - Redis is running: brew services list | grep redis"
        log_error "  - Redis is accessible: redis-cli ping"
        exit 1
    fi
    log_success "Redis connection OK"

    # Check database exists
    if ! mysql -h localhost -P 3306 -u trafficuser -ptrafficpass -e "USE trafficdb" &> /dev/null; then
        log_warning "Database 'trafficdb' not found. Creating..."
        mysql -h localhost -P 3306 -u trafficuser -ptrafficpass -e "CREATE DATABASE IF NOT EXISTS trafficdb"

        if [ -f "db/schema.sql" ]; then
            log_info "Applying schema from db/schema.sql..."
            mysql -h localhost -P 3306 -u trafficuser -ptrafficpass trafficdb < db/schema.sql
            log_success "Schema applied"
        fi
    fi
    log_success "Database 'trafficdb' exists"
}

# Main execution
case "${1:-all}" in
    check)
        check_prerequisites
        ;;

    openapi-proxy)
        export PORT=8082
        export DB_HOST=localhost
        export DB_PORT=3306
        export DB_USER=trafficuser
        export DB_PASSWORD=trafficpass
        export DB_NAME=trafficdb

        run_service "openapi-proxy-api" "openapi-proxy-api" 8082
        log_info "OpenAPI Proxy API running on http://localhost:8082"
        log_info "Test: curl http://localhost:8082/openapi/burstInfo/realTimeSms"
        ;;

    openapi-collector)
        export OPENAPI_URL=https://data.ex.co.kr/openapi/burstInfo/realTimeSms
        export OPENAPI_KEY=8771969304
        export DB_HOST=localhost
        export DB_PORT=3306
        export DB_USER=trafficuser
        export DB_PASSWORD=trafficpass
        export DB_NAME=trafficdb
        export COLLECT_INTERVAL=60s

        run_service "openapi-collector" "openapi-collector" 0
        log_info "OpenAPI Collector running (collecting from real OpenAPI)"
        ;;

    simulator)
        export PORT=8083
        export DB_HOST=localhost:3306
        export DB_USER=trafficuser
        export DB_PASSWORD=trafficpass
        export DB_NAME=trafficdb

        run_service "traffic-simulator" "traffic-simulator" 8083
        log_info "Traffic Simulator running on http://localhost:8083"
        log_info "Test: curl http://localhost:8083/api/traffic"
        ;;

    collector)
        export REDIS_ADDR=localhost:6379
        export SIMULATOR_API_URL=http://localhost:8083/api/traffic
        export REAL_OPENAPI_URL=http://localhost:8082/openapi/burstInfo/realTimeSms
        export COLLECT_INTERVAL=30s
        export DATA_SOURCE_MODE=sim

        run_service "data-collector" "data-collector" 0
        log_info "Data Collector running (no HTTP port)"
        log_info "  → Collecting from Simulator (localhost:8083)"
        ;;

    processor)
        export REDIS_HOST=localhost
        export REDIS_PORT=6379
        export DB_HOST=localhost
        export DB_PORT=3306
        export DB_USER=trafficuser
        export DB_PASSWORD=trafficpass
        export DB_NAME=trafficdb
        export STREAM_KEY=traffic-accidents
        export CONSUMER_GROUP=processor-group

        run_service "data-processor" "data-processor" 0
        log_info "Data Processor running (no HTTP port)"
        ;;

    api)
        export PORT=8081
        export DB_HOST=localhost:3306
        export DB_USER=trafficuser
        export DB_PASSWORD=trafficpass
        export DB_NAME=trafficdb

        run_service "data-api-service" "data-api-service" 8081
        log_info "Data API Service running on http://localhost:8081"
        log_info "Test: curl http://localhost:8081/api/accidents/latest"
        ;;

    gateway)
        export PORT=8080
        export DATA_API_SERVICE_URL=http://localhost:8081

        run_service "api-gateway" "api-gateway" 8080
        log_info "API Gateway running on http://localhost:8080"
        log_info "Test: curl http://localhost:8080/api/accidents/latest"
        ;;

    frontend)
        log_info "Starting frontend..."
        cd frontend

        # Install dependencies if needed
        if [ ! -d "node_modules" ]; then
            log_info "Installing npm dependencies..."
            npm install
        fi

        # Frontend uses .env.development automatically in dev mode
        # which should have REACT_APP_API_GATEWAY_URL=http://localhost:8080

        npm start > ../frontend.log 2>&1 &
        echo $! > ../.frontend.pid
        cd ..

        sleep 3
        log_success "Frontend starting on http://localhost:3000"
        log_info "  → API Gateway URL: http://localhost:8080"
        ;;

    all)
        log_info "========================================="
        log_info "Starting PlugFest 2025 Traffic Dashboard"
        log_info "========================================="
        echo ""

        check_prerequisites
        echo ""

        # Start services in dependency order
        log_info "Step 1/6: Starting Traffic Simulator..."
        $0 simulator
        sleep 3

        log_info "Step 2/6: Starting Data Collector..."
        $0 collector
        sleep 2

        log_info "Step 3/6: Starting Data Processor..."
        $0 processor
        sleep 2

        log_info "Step 4/6: Starting Data API Service..."
        $0 api
        sleep 2

        log_info "Step 5/6: Starting API Gateway..."
        $0 gateway
        sleep 2

        log_info "Step 6/6: Starting Frontend..."
        $0 frontend

        echo ""
        log_success "========================================="
        log_success "All services started successfully!"
        log_success "========================================="
        echo ""
        log_info "Service URLs:"
        log_info "  Frontend:          http://localhost:3000"
        log_info "  API Gateway:       http://localhost:8080/api/accidents/latest"
        log_info "  Data API Service:  http://localhost:8081/api/accidents/latest"
        log_info "  Traffic Simulator: http://localhost:8083/api/traffic"
        echo ""
        log_info "Logs: tail -f *.log"
        log_info "Status: $0 status"
        log_info "Stop: ./down-local.sh"
        ;;

    status)
        echo ""
        log_info "Service Status:"
        echo ""
        for pidfile in .*.pid; do
            if [ -f "$pidfile" ]; then
                service=$(basename "$pidfile" .pid | sed 's/^\.//')
                pid=$(cat "$pidfile")
                if kill -0 $pid 2>/dev/null; then
                    log_success "${service} is running (PID: ${pid})"
                else
                    log_error "${service} is not running"
                fi
            fi
        done
        echo ""
        ;;

    logs)
        service_name=${2:-all}
        if [ "$service_name" = "all" ]; then
            log_info "Showing all logs... (Ctrl+C to stop)"
            tail -f *.log 2>/dev/null || log_info "No log files found"
        else
            if [ -f "${service_name}.log" ]; then
                log_info "Showing ${service_name}.log... (Ctrl+C to stop)"
                tail -f ${service_name}.log
            else
                log_error "Log file ${service_name}.log not found"
                exit 1
            fi
        fi
        ;;

    *)
        echo "Usage: $0 {all|openapi-proxy|openapi-collector|collector|processor|api|gateway|frontend|check|status|logs}"
        echo ""
        echo "Commands:"
        echo "  all              - Start all services"
        echo "  openapi-proxy    - Start OpenAPI Proxy API only (port 8082)"
        echo "  openapi-collector- Start OpenAPI Collector only (collects from real API)"
        echo "  collector        - Start Data Collector only"
        echo "  processor        - Start Data Processor only"
        echo "  api              - Start Data API Service only (port 8081)"
        echo "  gateway          - Start API Gateway only (port 8080)"
        echo "  frontend         - Start Frontend only (port 3000)"
        echo "  check            - Check prerequisites (MariaDB, Redis)"
        echo "  status           - Show service status"
        echo "  logs [service]   - Show logs (all or specific service)"
        echo ""
        echo "Prerequisites:"
        echo "  - MariaDB running on localhost:3306"
        echo "  - Redis running on localhost:6379"
        echo "  - User: trafficuser/trafficpass"
        echo "  - Database: trafficdb"
        echo ""
        echo "Examples:"
        echo "  $0 check          # Check if MariaDB and Redis are running"
        echo "  $0 all            # Start all services"
        echo "  $0 status         # Check service status"
        echo "  $0 logs           # Show all logs"
        echo "  $0 logs frontend  # Show frontend logs only"
        echo "  ./down-local.sh   # Stop all services"
        exit 1
        ;;
esac
