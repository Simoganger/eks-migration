#!/usr/bin/env bash
# Update local kubeconfig for both clusters.
# Usage: ./setup-kubeconfig.sh [cluster1|cluster2|both]
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER1_NAME="${CLUSTER1_NAME:-eks-cluster-1}"
CLUSTER2_NAME="${CLUSTER2_NAME:-eks-cluster-2}"
TARGET="${1:-both}"

update_kubeconfig() {
  local name="$1"
  local alias="$2"
  echo "==> Updating kubeconfig for $name (alias: $alias)"
  aws eks update-kubeconfig \
    --name "$name" \
    --region "$AWS_REGION" \
    --alias "$alias"
  echo "    Done. Test: kubectl cluster-info --context $alias"
}

case "$TARGET" in
  cluster1) update_kubeconfig "$CLUSTER1_NAME" "cluster1" ;;
  cluster2) update_kubeconfig "$CLUSTER2_NAME" "cluster2" ;;
  both)
    update_kubeconfig "$CLUSTER1_NAME" "cluster1"
    update_kubeconfig "$CLUSTER2_NAME" "cluster2"
    ;;
  *)
    echo "Usage: $0 [cluster1|cluster2|both]"
    exit 1
    ;;
esac

echo ""
echo "Available contexts:"
kubectl config get-contexts
