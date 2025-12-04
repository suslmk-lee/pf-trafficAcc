#!/bin/bash

# ResourceBinding Cleanup Script
# Removes gracefulEvictionTasks from ResourceBindings to prevent stuck eviction states

set -e

CONTEXT="karmada-api-ctx"
NAMESPACE="tf-monitor"

echo "Checking ResourceBindings for gracefulEvictionTasks..."
echo "=========================================="

# Get all deployment ResourceBindings
BINDINGS=$(kubectl --context=${CONTEXT} --insecure-skip-tls-verify \
  get resourcebinding -n ${NAMESPACE} -o json | \
  jq -r '.items[] | select(.metadata.name | contains("deployment")) | .metadata.name')

FOUND_TASKS=0

for BINDING in $BINDINGS; do
  # Check if gracefulEvictionTasks exists
  TASKS=$(kubectl --context=${CONTEXT} --insecure-skip-tls-verify \
    get resourcebinding ${BINDING} -n ${NAMESPACE} -o jsonpath='{.spec.gracefulEvictionTasks}' 2>/dev/null || echo "")

  if [ ! -z "$TASKS" ] && [ "$TASKS" != "null" ]; then
    echo "Found gracefulEvictionTasks in: $BINDING"
    FOUND_TASKS=$((FOUND_TASKS + 1))

    # Remove gracefulEvictionTasks by patching
    echo "  → Removing gracefulEvictionTasks..."
    kubectl --context=${CONTEXT} --insecure-skip-tls-verify \
      patch resourcebinding ${BINDING} -n ${NAMESPACE} \
      --type=json \
      -p='[{"op":"remove","path":"/spec/gracefulEvictionTasks"}]' 2>/dev/null || true

    echo "  ✓ Cleaned"
  fi
done

echo ""
echo "=========================================="
if [ $FOUND_TASKS -eq 0 ]; then
  echo "✓ No gracefulEvictionTasks found. All ResourceBindings are clean."
else
  echo "✓ Cleaned $FOUND_TASKS ResourceBinding(s)"
fi

echo ""
echo "Current ResourceBinding distribution:"
kubectl --context=${CONTEXT} --insecure-skip-tls-verify \
  get resourcebinding -n ${NAMESPACE} -o json | \
  jq -r '.items[] | select(.metadata.name | contains("deployment")) | "\(.metadata.name): \(.spec.clusters | map(.name + "=" + (.replicas|tostring)) | join(", "))"'
