#!/bin/bash

# Traffic Monitoring System - Apply PropagationPolicy
# This script applies PropagationPolicy to propagate services to member clusters

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Apply PropagationPolicy${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster contexts
KARMADA_CTX="karmada-api-ctx"
MEMBER1_CTX="karmada-member1-ctx"
MEMBER2_CTX="karmada-member2-ctx"

# Check if contexts exist
echo -e "${YELLOW}[1/3] Checking cluster contexts...${NC}"
for ctx in $KARMADA_CTX $MEMBER1_CTX $MEMBER2_CTX; do
    if ! kubectl config get-contexts $ctx &> /dev/null; then
        echo -e "${RED}Error: Context $ctx not found${NC}"
        echo "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi
    echo "  ✓ Context $ctx found"
done
echo ""

# Step 1: Apply PropagationPolicy
echo -e "${YELLOW}[2/3] Applying PropagationPolicy...${NC}"
kubectl --context=$KARMADA_CTX apply -f k8s/karmada/propagation-policy.yaml
echo "  ✓ PropagationPolicy applied"
echo ""

# Step 2: Wait for pods to be ready in member1
echo -e "${YELLOW}[3/3] Waiting for pods to be ready in member1...${NC}"
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

# Final status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PropagationPolicy Applied!${NC}"
echo -e "${GREEN}========================================${NC}"
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

echo -e "${BLUE}Next Step:${NC} Run ./deploy-member.sh to deploy Istio resources"
echo ""
