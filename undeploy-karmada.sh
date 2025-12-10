#!/bin/bash

# Traffic Monitoring System - Undeploy from Karmada
# This script removes all application services from Karmada

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Karmada Undeploy (Application Services)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster context
KARMADA_CTX="karmada-api-ctx"

# Check if context exists
echo -e "${YELLOW}[1/6] Checking Karmada context...${NC}"
if ! kubectl config get-contexts $KARMADA_CTX &> /dev/null; then
    echo -e "${RED}Error: Context $KARMADA_CTX not found${NC}"
    exit 1
fi
echo "  ✓ Context $KARMADA_CTX found"
echo ""

# Step 1: Delete PropagationPolicy
echo -e "${YELLOW}[2/6] Deleting PropagationPolicy...${NC}"
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/propagation-policy.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/config-propagation.yaml --ignore-not-found=true
echo "  ✓ PropagationPolicy deleted"
echo ""

# Step 2: Delete services from Karmada
echo -e "${YELLOW}[3/6] Deleting services from Karmada...${NC}"
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/frontend.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/api-gateway.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/data-api-service.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/data-processor.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/data-collector.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/openapi-proxy-api.yaml --ignore-not-found=true
echo "  ✓ Services deleted from Karmada"
echo ""

# Step 3: Delete ConfigMap and Secret
echo -e "${YELLOW}[4/6] Deleting ConfigMap and Secret...${NC}"
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/config-and-secrets.yaml --ignore-not-found=true
echo "  ✓ ConfigMap and Secret deleted"
echo ""

# Step 4: Delete namespace
echo -e "${YELLOW}[5/6] Deleting tf-monitor namespace...${NC}"
kubectl --context=$KARMADA_CTX delete namespace tf-monitor --ignore-not-found=true --timeout=60s
echo "  ✓ Namespace deleted"
echo ""

# Step 5: Remove member2 taint
echo -e "${YELLOW}[6/6] Removing member2 taint...${NC}"
kubectl --context=$KARMADA_CTX patch cluster cp-plugfest-member2 --type=merge -p '{"spec":{"taints":[]}}' 2>/dev/null || true
echo "  ✓ Taint removed"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Karmada Undeploy Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
