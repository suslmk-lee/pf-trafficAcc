#!/bin/bash

# Traffic Monitoring System - Deploy to Member Clusters
# This script deploys Istio resources directly to member clusters

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Member Clusters Deploy (Istio Resources)${NC}"
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
        echo "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi
    echo "  ✓ Context $ctx found"
done
echo ""

# Step 1: Deploy Istio resources to member clusters
echo -e "${YELLOW}[2/2] Deploying Istio resources to member clusters...${NC}"
kubectl --context=$MEMBER1_CTX apply -f k8s/istio/gateway.yaml
kubectl --context=$MEMBER1_CTX apply -f k8s/istio/virtual-service.yaml
kubectl --context=$MEMBER1_CTX apply -f k8s/istio/destination-rule.yaml

kubectl --context=$MEMBER2_CTX apply -f k8s/istio/gateway.yaml
kubectl --context=$MEMBER2_CTX apply -f k8s/istio/virtual-service.yaml
kubectl --context=$MEMBER2_CTX apply -f k8s/istio/destination-rule.yaml
echo "  ✓ Istio resources deployed"
echo ""

# Final status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Member Clusters Deploy Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
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
