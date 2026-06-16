#!/usr/bin/env bash
# Progressively shift traffic from cluster1 to cluster2 via Route 53 weights.
# Usage: CLUSTER1_WEIGHT=90 CLUSTER2_WEIGHT=10 DRY_RUN=false ./03-traffic-shift.sh
set -euo pipefail

CLUSTER1_WEIGHT="${CLUSTER1_WEIGHT:-90}"
CLUSTER2_WEIGHT="${CLUSTER2_WEIGHT:-10}"
DRY_RUN="${DRY_RUN:-false}"
ACME_EMAIL="${ACME_EMAIL:-admin@navelmountech.com}"
TF_DIR="$(dirname "$0")/../infra/cluster2"

echo "==> Traffic shift plan"
echo "    cluster1: $CLUSTER1_WEIGHT"
echo "    cluster2: $CLUSTER2_WEIGHT"
echo ""

# Quick smoke test on cluster2 before shifting
CLUSTER2_LB=$(kubectl config use-context cluster2 && \
  kubectl get svc -n istio-system istio-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$CLUSTER2_LB" ]; then
  echo "ERROR: cluster2 Istio LB hostname not found. Is cluster2 ready?"
  exit 1
fi

echo "==> cluster2 LB: $CLUSTER2_LB"
echo "==> Testing cluster2 health endpoint..."
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
  --resolve "app.navelmountech.com:443:$(dig +short "$CLUSTER2_LB" | head -1)" \
  "https://app.navelmountech.com/health" || echo "000")
echo "    health status: $HTTP_STATUS"

if [ "$DRY_RUN" = "true" ]; then
  echo "[DRY RUN] Would update Route53 weights in $TF_DIR"
  exit 0
fi

echo "==> Applying Terraform to update Route 53 weights..."
cd "$TF_DIR"
terraform init -reconfigure
terraform apply \
  -var="cluster1_weight=$CLUSTER1_WEIGHT" \
  -var="cluster2_weight=$CLUSTER2_WEIGHT" \
  -var="acme_email=$ACME_EMAIL" \
  -target=module.route53 \
  -auto-approve

echo ""
echo "==> Traffic shifted: cluster1=$CLUSTER1_WEIGHT  cluster2=$CLUSTER2_WEIGHT"
echo "    Monitor error rates for at least 5 minutes before next shift."
echo "    Run smoke test: curl -sk https://app.navelmountech.com/health"
