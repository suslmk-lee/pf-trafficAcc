#!/bin/bash

# Traffic Monitoring System - Deploy to Karmada
# This script deploys all application services to Karmada

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Karmada Deploy (Application Services)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster contexts
KARMADA_CTX="karmada-api-ctx"
MEMBER1_CTX="karmada-member1-ctx"

# Check if contexts exist
echo -e "${YELLOW}[1/4] Checking cluster contexts...${NC}"
for ctx in $KARMADA_CTX $MEMBER1_CTX; do
    if ! kubectl config get-contexts $ctx &> /dev/null; then
        echo -e "${RED}Error: Context $ctx not found${NC}"
        echo "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi
    echo "  ✓ Context $ctx found"
done
echo ""

# Step 1: Create namespace in Karmada
echo -e "${YELLOW}[2/4] Creating tf-monitor namespace in Karmada...${NC}"
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/namespace.yaml
sleep 2
echo "  ✓ Namespace created"
echo ""

# Step 2: Deploy ConfigMap and Secret
echo -e "${YELLOW}[3/4] Deploying ConfigMap and Secret to Karmada...${NC}"
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/config-and-secrets.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/config-propagation.yaml
echo "  ✓ ConfigMap and Secret deployed"
echo ""

# Step 3: Apply member2 taint for Active-Standby
echo -e "${YELLOW}[4/4] Applying taint to member2 cluster and deploying services...${NC}"
kubectl --context=$KARMADA_CTX patch cluster cp-plugfest-member2 --type=merge -p '{"spec":{"taints":[{"key":"role","value":"standby","effect":"NoSchedule"}]}}'
echo "  ✓ Taint applied to member2"
echo ""

# Deploy all services to Karmada
echo "  Deploying services to Karmada..."
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/openapi-proxy-api.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/data-collector.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/data-processor.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/data-api-service.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/api-gateway.yaml
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/frontend.yaml
echo "  ✓ Services deployed to Karmada"
echo ""

# Final status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Karmada Resources Registered!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Registered Services in Karmada:${NC}"
kubectl --context=$KARMADA_CTX get deployments -n tf-monitor
echo ""

echo -e "${YELLOW}Member1 Status (No pods yet):${NC}"
kubectl --context=$MEMBER1_CTX get pods -n tf-monitor 2>/dev/null || echo "  No resources in member1 (PropagationPolicy not applied yet)"
echo ""

echo -e "${BLUE}Next Step:${NC} Run ./deploy-propagation.sh to propagate services to member clusters"
echo ""
