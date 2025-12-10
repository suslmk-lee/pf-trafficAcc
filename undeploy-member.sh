#!/bin/bash

# Traffic Monitoring System - Undeploy from Member Clusters
# This script removes Istio resources from member clusters

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Member Clusters Undeploy (Istio Resources)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster contexts
MEMBER1_CTX="karmada-member1-ctx"
MEMBER2_CTX="karmada-member2-ctx"

# Check if contexts exist
echo -e "${YELLOW}[1/2] Checking member cluster contexts...${NC}"
for ctx in $MEMBER1_CTX $MEMBER2_CTX; do
    if ! kubectl config get-contexts $ctx &> /dev/null; then
        echo -e "${RED}Error: Context $ctx not found${NC}"
        exit 1
    fi
    echo "  ✓ Context $ctx found"
done
echo ""

# Step 1: Delete Istio resources from member clusters
echo -e "${YELLOW}[2/2] Deleting Istio resources from member clusters...${NC}"
kubectl --context=$MEMBER1_CTX delete -f k8s/istio/gateway.yaml --ignore-not-found=true
kubectl --context=$MEMBER1_CTX delete -f k8s/istio/virtual-service.yaml --ignore-not-found=true
kubectl --context=$MEMBER1_CTX delete -f k8s/istio/destination-rule.yaml --ignore-not-found=true

kubectl --context=$MEMBER2_CTX delete -f k8s/istio/gateway.yaml --ignore-not-found=true
kubectl --context=$MEMBER2_CTX delete -f k8s/istio/virtual-service.yaml --ignore-not-found=true
kubectl --context=$MEMBER2_CTX delete -f k8s/istio/destination-rule.yaml --ignore-not-found=true
echo "  ✓ Istio resources deleted"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Member Clusters Undeploy Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
