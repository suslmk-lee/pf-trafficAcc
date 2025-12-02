#!/bin/bash

# PlugFest 2025 Traffic Dashboard Deployment Script
# High Availability Multi-Cluster Deployment Automation

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGISTRY="${DOCKER_REGISTRY:-registry.k-paas.org/plugfest}"
CENTRAL_CLUSTER="${CENTRAL_CLUSTER:-central-cluster}"
MEMBER1_CLUSTER="${MEMBER1_CLUSTER:-karmada-member1-ctx}"
MEMBER2_CLUSTER="${MEMBER2_CLUSTER:-karmada-member2-ctx}"
KARMADA_CONTEXT="${KARMADA_CONTEXT:-karmada-api-ctx}"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed. Aborting."; exit 1; }
    command -v docker >/dev/null 2>&1 || { log_error "docker is required but not installed. Aborting."; exit 1; }
    command -v karmadactl >/dev/null 2>&1 || { log_warning "karmadactl not found. Multi-cluster deployment may fail."; }

    log_success "Prerequisites check completed"
}

# Build Docker images
build_images() {
    log_info "Building Docker images..."

    services=("traffic-simulator" "data-collector" "data-processor" "data-api-service" "api-gateway" "frontend")

    for service in "${services[@]}"; do
        log_info "Building ${service}..."
        docker build -t ${REGISTRY}/${service}:latest ${service}/
        docker push ${REGISTRY}/${service}:latest
        log_success "${service} built and pushed"
    done

    log_success "All images built successfully"
}

# Deploy central cluster
deploy_central() {
    log_info "Deploying to central cluster..."

    kubectl config use-context ${CENTRAL_CLUSTER}

    log_info "Deploying MariaDB..."
    kubectl apply -f k8s/central/mariadb-central.yaml

    log_info "Waiting for MariaDB to be ready..."
    kubectl wait --for=condition=ready pod -l app=mariadb-central --timeout=300s

    log_info "Initializing database schema..."
    kubectl apply -f k8s/central/mariadb-schema-init.yaml
    kubectl wait --for=condition=complete job/mariadb-schema-init --timeout=120s

    log_info "Deploying Redis..."
    kubectl apply -f k8s/central/redis-central.yaml
    kubectl wait --for=condition=ready pod -l app=redis-central --timeout=120s

    log_info "Deploying traffic simulator..."
    kubectl apply -f k8s/central/traffic-simulator.yaml
    kubectl wait --for=condition=ready pod -l app=traffic-simulator --timeout=60s

    log_success "Central cluster deployment completed"
}

# Configure Istio ServiceEntry
configure_istio() {
    log_info "Configuring Istio ServiceEntry..."

    kubectl config use-context ${CENTRAL_CLUSTER}

    MARIADB_IP=$(kubectl get svc mariadb-central -o jsonpath='{.spec.clusterIP}')
    REDIS_IP=$(kubectl get svc redis-central -o jsonpath='{.spec.clusterIP}')
    SIMULATOR_IP=$(kubectl get svc traffic-simulator -o jsonpath='{.spec.clusterIP}')

    log_info "Central service IPs:"
    log_info "  MariaDB: ${MARIADB_IP}"
    log_info "  Redis: ${REDIS_IP}"
    log_info "  Simulator: ${SIMULATOR_IP}"

    # Create temporary file with replaced IPs
    cp k8s/istio/service-entry.yaml k8s/istio/service-entry.yaml.tmp
    sed -i.bak "s/MARIADB_CENTRAL_IP/${MARIADB_IP}/g" k8s/istio/service-entry.yaml.tmp
    sed -i.bak "s/REDIS_CENTRAL_IP/${REDIS_IP}/g" k8s/istio/service-entry.yaml.tmp
    sed -i.bak "s/TRAFFIC_SIMULATOR_IP/${SIMULATOR_IP}/g" k8s/istio/service-entry.yaml.tmp

    log_success "Istio ServiceEntry configured"
}

# Deploy to Karmada
deploy_karmada() {
    log_info "Deploying to Karmada..."

    kubectl config use-context ${KARMADA_CONTEXT}

    # Create namespace with Istio injection enabled in member clusters
    log_info "Creating tf-monitor namespace with Istio injection..."
    for cluster in ${MEMBER1_CLUSTER} ${MEMBER2_CLUSTER}; do
        kubectl --context ${cluster} apply -f k8s/karmada/namespace.yaml
        log_success "Namespace created in ${cluster}"
    done

    # Create secrets and configmaps
    log_info "Creating config and secrets..."
    kubectl apply -f k8s/karmada/config-and-secrets.yaml
    kubectl apply -f k8s/karmada/config-propagation.yaml

    log_info "Waiting for config propagation..."
    sleep 3

    # Deploy services
    log_info "Deploying services to Karmada..."
    kubectl apply -f k8s/karmada/openapi-proxy-api.yaml
    kubectl apply -f k8s/karmada/data-collector.yaml
    kubectl apply -f k8s/karmada/data-processor.yaml
    kubectl apply -f k8s/karmada/data-api-service.yaml
    kubectl apply -f k8s/karmada/api-gateway.yaml
    kubectl apply -f k8s/karmada/frontend.yaml

    # Apply propagation policies
    log_info "Applying propagation policies..."
    kubectl apply -f k8s/karmada/propagation-policy.yaml
    kubectl apply -f k8s/karmada/openapi-proxy-propagation.yaml

    log_success "Karmada deployment completed"
}

# Deploy Istio configurations
deploy_istio() {
    log_info "Deploying Istio configurations..."

    for cluster in ${MEMBER1_CLUSTER} ${MEMBER2_CLUSTER}; do
        log_info "Configuring Istio in ${cluster}..."
        kubectl config use-context ${cluster}

        kubectl apply -f k8s/istio/gateway.yaml -n tf-monitor
        kubectl apply -f k8s/istio/virtual-service.yaml -n tf-monitor
        kubectl apply -f k8s/istio/destination-rule.yaml -n tf-monitor
        kubectl apply -f k8s/istio/service-entry.yaml.tmp -n tf-monitor

        log_success "Istio configured in ${cluster}"
    done

    # Cleanup temporary file
    rm -f k8s/istio/service-entry.yaml.tmp k8s/istio/service-entry.yaml.tmp.bak

    log_success "Istio deployment completed"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."

    kubectl config use-context ${KARMADA_CONTEXT}

    log_info "Karmada ResourceBindings:"
    kubectl get resourcebinding

    log_info "Checking member clusters..."
    for cluster in ${MEMBER1_CLUSTER} ${MEMBER2_CLUSTER}; do
        log_info "Pods in ${cluster}:"
        kubectl --context ${cluster} get pods -n tf-monitor
    done

    log_success "Deployment verification completed"
}

# Main deployment flow
main() {
    echo "========================================="
    echo "PlugFest 2025 Traffic Dashboard"
    echo "High Availability Deployment"
    echo "========================================="
    echo ""

    case "${1:-all}" in
        prereq)
            check_prerequisites
            ;;
        build)
            check_prerequisites
            build_images
            ;;
        central)
            check_prerequisites
            deploy_central
            ;;
        karmada)
            check_prerequisites
            configure_istio
            deploy_karmada
            ;;
        istio)
            check_prerequisites
            configure_istio
            deploy_istio
            ;;
        verify)
            verify_deployment
            ;;
        all)
            check_prerequisites
            build_images
            deploy_central
            configure_istio
            deploy_karmada
            deploy_istio
            verify_deployment
            log_success "Full deployment completed successfully!"
            ;;
        *)
            echo "Usage: $0 {all|prereq|build|central|karmada|istio|verify}"
            echo ""
            echo "Commands:"
            echo "  all      - Full deployment (default)"
            echo "  prereq   - Check prerequisites only"
            echo "  build    - Build and push Docker images"
            echo "  central  - Deploy central cluster only"
            echo "  karmada  - Deploy to Karmada only"
            echo "  istio    - Deploy Istio configurations only"
            echo "  verify   - Verify deployment"
            exit 1
            ;;
    esac
}

main "$@"
