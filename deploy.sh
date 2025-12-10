#!/bin/bash

# Traffic Monitoring System - Deploy Script
# This script deploys the entire system to Karmada and member clusters

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Traffic Monitoring System - Deploy${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster contexts
KARMADA_CTX="karmada-api-ctx"
MEMBER1_CTX="karmada-member1-ctx"
MEMBER2_CTX="karmada-member2-ctx"
CENTRAL_CTX="central-ctx"

# Check if contexts exist
echo -e "${YELLOW}[1/13] Checking cluster contexts...${NC}"
for ctx in $KARMADA_CTX $MEMBER1_CTX $MEMBER2_CTX $CENTRAL_CTX; do
    if ! kubectl config get-contexts $ctx &> /dev/null; then
        echo -e "${RED}Error: Context $ctx not found${NC}"
        echo "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi
    echo "  ✓ Context $ctx found"
done
echo ""

# Step 1: Deploy MariaDB and Redis to Central cluster
echo -e "${YELLOW}[2/13] Deploying MariaDB and Redis to central cluster...${NC}"
kubectl --context=$CENTRAL_CTX apply -f k8s/central/mariadb-central.yaml
kubectl --context=$CENTRAL_CTX apply -f k8s/central/redis-central.yaml
echo "  ✓ MariaDB and Redis deployed"
echo ""

# Step 2: Wait for MariaDB and Redis to be ready
echo -e "${YELLOW}[3/13] Waiting for MariaDB and Redis to be ready...${NC}"
echo "  Waiting for MariaDB PVC to be bound..."
kubectl --context=$CENTRAL_CTX wait --for=jsonpath='{.status.phase}'=Bound pvc/mariadb-pvc -n default --timeout=300s
echo "  ✓ MariaDB PVC bound"

echo "  Waiting for Redis PVC to be bound..."
kubectl --context=$CENTRAL_CTX wait --for=jsonpath='{.status.phase}'=Bound pvc/redis-pvc -n default --timeout=300s
echo "  ✓ Redis PVC bound"

echo "  Waiting for MariaDB pod to be ready..."
kubectl --context=$CENTRAL_CTX wait --for=condition=ready pod -l app=mariadb-central -n default --timeout=300s
echo "  ✓ MariaDB ready"

echo "  Waiting for Redis pod to be ready..."
kubectl --context=$CENTRAL_CTX wait --for=condition=ready pod -l app=redis-central -n default --timeout=300s
echo "  ✓ Redis ready"
echo ""

# Step 3: Initialize MariaDB schema
echo -e "${YELLOW}[4/13] Initializing MariaDB schema...${NC}"
kubectl --context=$CENTRAL_CTX apply -f k8s/central/mariadb-schema-init.yaml
echo "  Waiting for schema initialization job to complete..."
kubectl --context=$CENTRAL_CTX wait --for=condition=complete job/mariadb-schema-init -n default --timeout=300s
echo "  ✓ Database schema initialized"
echo ""

# Step 4: Add cache tables
echo -e "${YELLOW}[5/13] Adding cache tables to MariaDB...${NC}"
kubectl --context=$CENTRAL_CTX create configmap mariadb-cache-tables --from-file=db/add-cache-tables.sql -n default --dry-run=client -o yaml | kubectl --context=$CENTRAL_CTX apply -f -
kubectl --context=$CENTRAL_CTX apply -f k8s/central/mariadb-cache-tables-job.yaml
echo "  Waiting for cache tables job to complete..."
kubectl --context=$CENTRAL_CTX wait --for=condition=complete job/mariadb-add-cache-tables -n default --timeout=300s
echo "  ✓ Cache tables added"
echo ""

# Step 5: Add tollgate tables
echo -e "${YELLOW}[6/13] Adding tollgate tables to MariaDB...${NC}"
kubectl --context=$CENTRAL_CTX create configmap tollgate-schema --from-file=db/schema_tollgate_traffic.sql -n default --dry-run=client -o yaml | kubectl --context=$CENTRAL_CTX apply -f -
kubectl --context=$CENTRAL_CTX apply -f k8s/central/tollgate-schema-job.yaml
echo "  Waiting for tollgate tables job to complete..."
kubectl --context=$CENTRAL_CTX wait --for=condition=complete job/mariadb-add-tollgate-tables -n default --timeout=300s
echo "  ✓ Tollgate tables added"
echo ""

# Step 6: Create namespace in Karmada
echo -e "${YELLOW}[7/13] Creating tf-monitor namespace in Karmada...${NC}"
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/namespace.yaml
sleep 2
echo "  ✓ Namespace created"
echo ""

# Step 7: Deploy ConfigMap and Secret
echo -e "${YELLOW}[8/13] Deploying ConfigMap and Secret to Karmada...${NC}"
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/config-and-secrets.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/config-propagation.yaml
echo "  ✓ ConfigMap and Secret deployed"
echo ""

# Step 8: Apply member2 taint for Active-Standby
echo -e "${YELLOW}[9/13] Applying taint to member2 cluster...${NC}"
kubectl --context=$KARMADA_CTX patch cluster cp-plugfest-member2 --type=merge -p '{"spec":{"taints":[{"key":"role","value":"standby","effect":"NoSchedule"}]}}'
echo "  ✓ Taint applied to member2"
echo ""

# Step 9: Deploy all services to Karmada
echo -e "${YELLOW}[10/13] Deploying services to Karmada...${NC}"
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/openapi-proxy-api.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/data-collector.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/data-processor.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/data-api-service.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/api-gateway.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/frontend.yaml
echo "  ✓ Services deployed to Karmada"
echo ""

# Step 10: Apply PropagationPolicy
echo -e "${YELLOW}[11/13] Applying PropagationPolicy...${NC}"
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/propagation-policy.yaml
echo "  ✓ PropagationPolicy applied"
echo ""

# Step 11: Wait for pods to be ready in member1
echo -e "${YELLOW}[12/13] Waiting for pods to be ready in member1...${NC}"
echo "  This may take a few minutes..."
sleep 15
kubectl --context=$MEMBER1_CTX wait --for=condition=ready pod -l app=frontend -n tf-monitor --timeout=300s
kubectl --context=$MEMBER1_CTX wait --for=condition=ready pod -l app=api-gateway -n tf-monitor --timeout=300s
kubectl --context=$MEMBER1_CTX wait --for=condition=ready pod -l app=data-api-service -n tf-monitor --timeout=300s
kubectl --context=$MEMBER1_CTX wait --for=condition=ready pod -l app=data-processor -n tf-monitor --timeout=300s
kubectl --context=$MEMBER1_CTX wait --for=condition=ready pod -l app=data-collector -n tf-monitor --timeout=300s
kubectl --context=$MEMBER1_CTX wait --for=condition=ready pod -l app=openapi-proxy-api -n tf-monitor --timeout=300s
echo "  ✓ All pods ready in member1"
echo ""

# Step 12: Deploy Istio resources to member clusters
echo -e "${YELLOW}[13/13] Deploying Istio resources to member clusters...${NC}"
kubectl --context=$MEMBER1_CTX apply -f k8s/istio/gateway.yaml
kubectl --context=$MEMBER1_CTX apply -f k8s/istio/virtual-service.yaml
kubectl --context=$MEMBER1_CTX apply -f k8s/istio/destination-rule.yaml

kubectl --context=$MEMBER2_CTX apply -f k8s/istio/gateway.yaml
kubectl --context=$MEMBER2_CTX apply -f k8s/istio/virtual-service.yaml
kubectl --context=$MEMBER2_CTX apply -f k8s/istio/destination-rule.yaml
echo "  ✓ Istio resources deployed"
echo ""

# Final verification
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploy completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}Deployment Status:${NC}"
echo ""
echo -e "${YELLOW}Central Cluster:${NC}"
kubectl --context=$CENTRAL_CTX get pods -n default | grep -E "mariadb|redis"
echo ""

echo -e "${YELLOW}Karmada ResourceBindings:${NC}"
kubectl --context=$KARMADA_CTX get resourcebinding -n tf-monitor -o custom-columns=NAME:.metadata.name,CLUSTERS:.spec.clusters[*].name --no-headers
echo ""

echo -e "${YELLOW}Member1 Pods:${NC}"
kubectl --context=$MEMBER1_CTX get pods -n tf-monitor
echo ""

echo -e "${YELLOW}Member2 Pods (should be empty - standby):${NC}"
kubectl --context=$MEMBER2_CTX get pods -n tf-monitor 2>/dev/null || echo "  No pods (standby mode)"
echo ""

echo -e "${YELLOW}Istio Ingress Gateway:${NC}"
echo -e "  Member1: $(kubectl --context=$MEMBER1_CTX get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo -e "  Member2: $(kubectl --context=$MEMBER2_CTX get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo ""

echo -e "${GREEN}Frontend Access:${NC}"
MEMBER1_IP=$(kubectl --context=$MEMBER1_CTX get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo -e "  http://${MEMBER1_IP}/"
echo ""

echo -e "${YELLOW}System is ready for demo!${NC}"
echo ""
