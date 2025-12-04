#!/bin/bash

# Sequential WorkloadRebalancer Script
# Rebalances services one by one with 2 second intervals to avoid scheduling conflicts

set -e

CONTEXT="karmada-api-ctx"
NAMESPACE="tf-monitor"
DELAY=2

# Services to rebalance (in order)
SERVICES=(
  "data-collector"
  "data-processor"
  "data-api-service"
  "api-gateway"
  "frontend"
  "openapi-proxy-api"
)

echo "Starting sequential workload rebalancing..."
echo "Context: $CONTEXT"
echo "Namespace: $NAMESPACE"
echo "Delay: ${DELAY}s between services"
echo "----------------------------------------"

# Step 1: Clean up any stuck gracefulEvictionTasks
echo ""
echo "Step 1: Cleaning up ResourceBindings..."
echo "=========================================="

CLEANUP_SCRIPT="$(dirname "$0")/cleanup-resourcebindings.sh"
if [ -x "$CLEANUP_SCRIPT" ]; then
  "$CLEANUP_SCRIPT"
  echo ""
else
  echo "Warning: cleanup-resourcebindings.sh not found or not executable"
  echo ""
fi

echo "=========================================="
echo "Step 2: Sequential Workload Rebalancing"
echo "=========================================="

TOTAL_SERVICES=${#SERVICES[@]}
CURRENT=0

for SERVICE in "${SERVICES[@]}"; do
  CURRENT=$((CURRENT + 1))
  echo ""
  echo "[$(date +%H:%M:%S)] Rebalancing $CURRENT/$TOTAL_SERVICES: $SERVICE"

  # Create temporary WorkloadRebalancer manifest
  cat > /tmp/${SERVICE}-rebalance.yaml <<EOF
apiVersion: apps.karmada.io/v1alpha1
kind: WorkloadRebalancer
metadata:
  name: ${SERVICE}-rebalance
spec:
  workloads:
    - apiVersion: apps/v1
      kind: Deployment
      name: ${SERVICE}
      namespace: ${NAMESPACE}
  ttlSecondsAfterFinished: 300
EOF

  # Apply WorkloadRebalancer
  kubectl apply -f /tmp/${SERVICE}-rebalance.yaml \
    --context=${CONTEXT} \
    --insecure-skip-tls-verify

  # Clean up temp file
  rm -f /tmp/${SERVICE}-rebalance.yaml

  # Wait before next service (except for last one)
  if [ $CURRENT -lt $TOTAL_SERVICES ]; then
    echo "  → Waiting ${DELAY}s before next service..."
    sleep $DELAY
  fi
done

echo ""
echo "----------------------------------------"
echo "Sequential rebalancing completed!"
echo ""
echo "Waiting 30s for Karmada to process..."
sleep 30

echo ""
echo "Current ResourceBinding distribution:"
kubectl --context=${CONTEXT} --insecure-skip-tls-verify \
  get resourcebinding -n ${NAMESPACE} -o json | \
  jq -r '.items[] | select(.metadata.name | contains("deployment")) | "\(.metadata.name): \(.spec.clusters | map(.name + "=" + (.replicas|tostring)) | join(", "))"'

echo ""
echo "Done!"
