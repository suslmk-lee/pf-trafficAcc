#!/bin/bash

# Traffic Monitoring System - Undeploy Central Cluster (MariaDB + Redis)
# This script removes MariaDB and Redis from the central cluster

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Central Cluster Undeploy (MariaDB + Redis)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster context
CENTRAL_CTX="central-ctx"

# Check if context exists
echo -e "${YELLOW}[1/3] Checking central cluster context...${NC}"
if ! kubectl config get-contexts $CENTRAL_CTX &> /dev/null; then
    echo -e "${RED}Error: Context $CENTRAL_CTX not found${NC}"
    exit 1
fi
echo "  ✓ Context $CENTRAL_CTX found"
echo ""

# Step 1: Delete jobs and configmaps
echo -e "${YELLOW}[2/3] Deleting jobs and configmaps from central cluster...${NC}"
kubectl --context=$CENTRAL_CTX delete job mariadb-schema-init -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete job mariadb-add-cache-tables -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete job mariadb-add-tollgate-tables -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete configmap mariadb-init-schema -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete configmap mariadb-cache-tables -n default --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete configmap tollgate-schema -n default --ignore-not-found=true
echo "  ✓ Jobs and configmaps deleted"
echo ""

# Step 2: Delete MariaDB and Redis
echo -e "${YELLOW}[3/3] Deleting MariaDB and Redis from central cluster...${NC}"
kubectl --context=$CENTRAL_CTX delete -f k8s/central/mariadb-central.yaml --ignore-not-found=true
kubectl --context=$CENTRAL_CTX delete -f k8s/central/redis-central.yaml --ignore-not-found=true
echo "  ✓ MariaDB and Redis deleted"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Central Cluster Undeploy Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Note: PVCs are not automatically deleted. To delete them:${NC}"
echo "  kubectl --context=$CENTRAL_CTX delete pvc mariadb-pvc redis-pvc -n default"
echo ""
