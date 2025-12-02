#!/bin/bash

# PlugFest 2025 Traffic Dashboard - Service Restart Script

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

# Function to restart a service
restart_service() {
    local service_arg=$1    # Argument for run-local.sh
    local service_name=$2   # PID file name

    log_info "Restarting ${service_name}..."

    # Stop the service
    if [ -f ".${service_name}.pid" ]; then
        local pid=$(cat ".${service_name}.pid")
        if kill -0 $pid 2>/dev/null; then
            log_info "Stopping ${service_name} (PID: ${pid})..."
            kill $pid 2>/dev/null || true
            sleep 2

            # Force kill if still running
            if kill -0 $pid 2>/dev/null; then
                log_warning "Force killing ${service_name}..."
                kill -9 $pid 2>/dev/null || true
                sleep 1
            fi
        fi
        rm -f ".${service_name}.pid"
    else
        log_warning "PID file not found for ${service_name}, trying to kill by process name..."
        pkill -f "${service_name}/main.go" 2>/dev/null || true
        if [ "$service_name" = "frontend" ]; then
            pkill -f "react-scripts start" 2>/dev/null || true
        fi
        sleep 2
    fi

    # Start the service
    ./run-local.sh ${service_arg}

    sleep 2
    log_success "${service_name} restarted successfully"
    echo ""
}

# Main execution
case "${1:-help}" in
    simulator)
        restart_service "simulator" "traffic-simulator"
        ;;

    collector)
        restart_service "collector" "data-collector"
        ;;

    processor)
        restart_service "processor" "data-processor"
        ;;

    api)
        restart_service "api" "data-api-service"
        ;;

    gateway)
        restart_service "gateway" "api-gateway"
        ;;

    frontend)
        restart_service "frontend" "frontend"
        ;;

    all)
        log_info "========================================="
        log_info "Restarting All Services"
        log_info "========================================="
        echo ""

        restart_service "simulator" "traffic-simulator"
        restart_service "collector" "data-collector"
        restart_service "processor" "data-processor"
        restart_service "api" "data-api-service"
        restart_service "gateway" "api-gateway"
        restart_service "frontend" "frontend"

        echo ""
        log_success "========================================="
        log_success "All services restarted!"
        log_success "========================================="
        echo ""
        log_info "Check status: ./run-local.sh status"
        ;;

    backend)
        log_info "========================================="
        log_info "Restarting Backend Services"
        log_info "========================================="
        echo ""

        restart_service "simulator" "traffic-simulator"
        restart_service "collector" "data-collector"
        restart_service "processor" "data-processor"
        restart_service "api" "data-api-service"
        restart_service "gateway" "api-gateway"

        echo ""
        log_success "Backend services restarted!"
        ;;

    help|*)
        echo "Usage: $0 {service|all|backend}"
        echo ""
        echo "Services:"
        echo "  simulator   - Restart Traffic Simulator"
        echo "  collector   - Restart Data Collector"
        echo "  processor   - Restart Data Processor"
        echo "  api         - Restart Data API Service"
        echo "  gateway     - Restart API Gateway"
        echo "  frontend    - Restart Frontend"
        echo ""
        echo "Groups:"
        echo "  all         - Restart all services"
        echo "  backend     - Restart all backend services (excluding frontend)"
        echo ""
        echo "Examples:"
        echo "  $0 api          # Restart Data API Service only"
        echo "  $0 collector    # Restart Data Collector only"
        echo "  $0 backend      # Restart all backend services"
        echo "  $0 all          # Restart everything"
        echo ""
        exit 1
        ;;
esac
