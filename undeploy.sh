#!/bin/bash

# Traffic Monitoring System - Undeploy Script
# This script removes all deployed resources from Karmada and member clusters

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Traffic Monitoring System - Undeploy${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster contexts
KARMADA_CTX="karmada-api-ctx"
MEMBER1_CTX="karmada-member1-ctx"
MEMBER2_CTX="karmada-member2-ctx"
CENTRAL_CTX="central-ctx"

# Check if contexts exist
echo -e "${YELLOW}[1/9] Checking cluster contexts...${NC}"
for ctx in $KARMADA_CTX $MEMBER1_CTX $MEMBER2_CTX $CENTRAL_CTX; do
    if ! kubectl config get-contexts $ctx &> /dev/null; then
        echo -e "${RED}Error: Context $ctx not found${NC}"
        exit 1
    fi
    echo "  ✓ Context $ctx found"
done
echo ""

# Step 1: Delete Istio resources from member clusters
echo -e "${YELLOW}[2/9] Deleting Istio resources from member clusters...${NC}"
kubectl --context=$MEMBER1_CTX delete -f k8s/istio/gateway.yaml --ignore-not-found=true
kubectl --context=$MEMBER1_CTX delete -f k8s/istio/virtual-service.yaml --ignore-not-found=true
kubectl --context=$MEMBER1_CTX delete -f k8s/istio/destination-rule.yaml --ignore-not-found=true

kubectl --context=$MEMBER2_CTX delete -f k8s/istio/gateway.yaml --ignore-not-found=true
kubectl --context=$MEMBER2_CTX delete -f k8s/istio/virtual-service.yaml --ignore-not-found=true
kubectl --context=$MEMBER2_CTX delete -f k8s/istio/destination-rule.yaml --ignore-not-found=true
echo "  ✓ Istio resources deleted"
echo ""

# Step 2: Delete PropagationPolicy
echo -e "${YELLOW}[3/9] Deleting PropagationPolicy...${NC}"
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/propagation-policy.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/config-propagation.yaml --ignore-not-found=true
echo "  ✓ PropagationPolicy deleted"
echo ""

# Step 3: Delete services from Karmada
echo -e "${YELLOW}[4/9] Deleting services from Karmada...${NC}"
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/frontend.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/api-gateway.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/data-api-service.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/data-processor.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/data-collector.yaml --ignore-not-found=true
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/openapi-proxy-api.yaml --ignore-not-found=true
echo "  ✓ Services deleted from Karmada"
echo ""

# Step 4: Delete ConfigMap and Secret
echo -e "${YELLOW}[5/9] Deleting ConfigMap and Secret...${NC}"
kubectl --context=$KARMADA_CTX delete -f k8s/karmada/config-and-secrets.yaml --ignore-not-found=true
echo "  ✓ ConfigMap and Secret deleted"
echo ""

# Step 5: Delete namespace (this will cascade delete everything in it)
echo -e "${YELLOW}[6/9] Deleting tf-monitor namespace...${NC}"
kubectl --context=$KARMADA_CTX delete namespace tf-monitor --ignore-not-found=true --timeout=60s
echo "  ✓ Namespace deleted"
echo ""

# Step 6: Remove member2 taint
echo -e "${YELLOW}[7/9] Removing member2 taint...${NC}"
kubectl --context=$KARMADA_CTX patch cluster cp-plugfest-member2 --type=merge -p '{"spec":{"taints":[]}}' 2>/dev/null || true
echo "  ✓ Taint removed"
echo ""

# Step 7: Delete jobs from central cluster
echo -e "${YELLOW}[8/9] Deleting jobs from central cluster...${NC}"
kubectl --context=$CENTRAL_CTX delete job mariadb-schema-init -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete job mariadb-add-cache-tables -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete job mariadb-add-tollgate-tables -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete configmap mariadb-init-schema -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete configmap mariadb-cache-tables -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete configmap tollgate-schema -n default --ignore-not-found=true
echo "  ✓ Jobs deleted"
echo ""

# Step 8: Delete MariaDB and Redis from central cluster
echo -e "${YELLOW}[9/9] Deleting MariaDB and Redis from central cluster...${NC}"
kubectl --context=$CENTRAL_CTX delete -f k8s/central/mariadb-central.yaml --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete -f k8s/central/redis-central.yaml --ignore-not-found=true
echo "  ✓ MariaDB and Redis deleted"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Undeploy completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Note: PVCs are not automatically deleted. To delete them:${NC}"
echo "  kubectl --context=$CENTRAL_CTX delete pvc mariadb-pvc redis-pvc -n default"
echo ""
