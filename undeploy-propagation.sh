#!/bin/bash

# Traffic Monitoring System - Remove PropagationPolicy
# This script removes PropagationPolicy (services remain in Karmada but are removed from member clusters)

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Remove PropagationPolicy${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster context
KARMADA_CTX="karmada-api-ctx"
MEMBER1_CTX="karmada-member1-ctx"

# Check if context exists
echo -e "${YELLOW}[1/2] Checking Karmada context...${NC}"
if ! kubectl config get-contexts $KARMADA_CTX &> /dev/null; then
    echo -e "${RED}Error: Context $KARMADA_CTX not found${NC}"
    exit 1
fi
echo "  ✓ Context $KARMADA_CTX found"
echo ""

# Step 1: Delete PropagationPolicy
echo -e "${YELLOW}[2/2] Deleting PropagationPolicy...${NC}"
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/propagation-policy.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/config-propagation.yaml --ignore-not-found=true
echo "  ✓ PropagationPolicy deleted"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PropagationPolicy Removed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Services still registered in Karmada:${NC}"
kubectl --context=$KARMADA_CTX get deployments -n tf-monitor
echo ""

echo -e "${YELLOW}Member1 Pods (should be terminating):${NC}"
kubectl --context=$MEMBER1_CTX get pods -n tf-monitor 2>/dev/null || echo "  No pods"
echo ""
