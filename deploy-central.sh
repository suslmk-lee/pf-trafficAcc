#!/bin/bash

# Traffic Monitoring System - Deploy Central Cluster (MariaDB + Redis)
# This script deploys MariaDB and Redis to the central cluster

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Central Cluster Deploy (MariaDB + Redis)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Cluster context
CENTRAL_CTX="central-ctx"

# Check if context exists
echo -e "${YELLOW}[1/6] Checking central cluster context...${NC}"
if ! kubectl config get-contexts $CENTRAL_CTX &> /dev/null; then
    echo -e "${RED}Error: Context $CENTRAL_CTX not found${NC}"
    echo "Available contexts:"
    kubectl config get-contexts
    exit 1
fi
echo "  ✓ Context $CENTRAL_CTX found"
echo ""

# Step 1: Deploy MariaDB and Redis
echo -e "${YELLOW}[2/6] Deploying MariaDB and Redis to central cluster...${NC}"
kubectl --context=$CENTRAL_CTX apply -f k8s/central/mariadb-central.yaml
kubectl --context=$CENTRAL_CTX apply -f k8s/central/redis-central.yaml
echo "  ✓ MariaDB and Redis deployed"
echo ""

# Step 2: Wait for MariaDB and Redis to be ready
echo -e "${YELLOW}[3/6] Waiting for MariaDB and Redis to be ready...${NC}"
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
echo -e "${YELLOW}[4/6] Initializing MariaDB schema...${NC}"
kubectl --context=$CENTRAL_CTX apply -f k8s/central/mariadb-schema-init.yaml
echo "  Waiting for schema initialization job to complete..."
kubectl --context=$CENTRAL_CTX wait --for=condition=complete job/mariadb-schema-init -n default --timeout=300s
echo "  ✓ Database schema initialized"
echo ""

# Step 4: Add cache tables
echo -e "${YELLOW}[5/6] Adding cache tables to MariaDB...${NC}"
kubectl --context=$CENTRAL_CTX create configmap mariadb-cache-tables --from-file=db/add-cache-tables.sql -n default --dry-run=client -o yaml | kubectl --context=$CENTRAL_CTX apply -f -
kubectl --context=$CENTRAL_CTX apply -f k8s/central/mariadb-cache-tables-job.yaml
echo "  Waiting for cache tables job to complete..."
kubectl --context=$CENTRAL_CTX wait --for=condition=complete job/mariadb-add-cache-tables -n default --timeout=300s
echo "  ✓ Cache tables added"
echo ""

# Step 5: Add tollgate tables
echo -e "${YELLOW}[6/6] Adding tollgate tables to MariaDB...${NC}"
kubectl --context=$CENTRAL_CTX create configmap tollgate-schema --from-file=db/schema_tollgate_traffic.sql -n default --dry-run=client -o yaml | kubectl --context=$CENTRAL_CTX apply -f -
kubectl --context=$CENTRAL_CTX apply -f k8s/central/tollgate-schema-job.yaml
echo "  Waiting for tollgate tables job to complete..."
kubectl --context=$CENTRAL_CTX wait --for=condition=complete job/mariadb-add-tollgate-tables -n default --timeout=300s
echo "  ✓ Tollgate tables added"
echo ""

# Final status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Central Cluster Deploy Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Central Cluster Status:${NC}"
kubectl --context=$CENTRAL_CTX get pods -n default | grep -E "mariadb|redis"
echo ""

echo -e "${BLUE}MariaDB Endpoint:${NC} 210.109.14.158:30306"
echo -e "${BLUE}Redis Endpoint:${NC} 210.109.14.158:30379"
echo ""
