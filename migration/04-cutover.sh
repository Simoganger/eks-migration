#!/usr/bin/env bash
# Final cutover: set cluster2 to 100% and drain cluster1.
# After this script, cluster1 can be decommissioned.
# Usage: DRY_RUN=false ./04-cutover.sh
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
ACME_EMAIL="${ACME_EMAIL:-admin@navelmountech.com}"
TF_DIR="$(dirname "$0")/../infra/cluster2"

echo "============================================================"
echo "  FINAL CUTOVER: 100% traffic to cluster2"
echo "============================================================"
echo ""
echo "This will:"
echo "  1. Set Route 53: cluster1=0, cluster2=100"
echo "  2. Scale down taskmanager on cluster1 to 0"
echo "  3. Create a final archive backup on cluster1"
echo ""
read -r -p "Are you sure? Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 1; }

echo ""
echo "==> Step 1: Set Route 53 to 100% cluster2"
if [ "$DRY_RUN" != "true" ]; then
  cd "$TF_DIR"
  terraform init -reconfigure
  terraform apply \
    -var="cluster1_weight=0" \
    -var="cluster2_weight=100" \
    -var="acme_email=$ACME_EMAIL" \
    -target=module.route53 \
    -auto-approve
  cd -
fi

echo "==> Step 2: Scale down cluster1 taskmanager deployment"
if [ "$DRY_RUN" != "true" ]; then
  kubectl config use-context cluster1
  kubectl scale deployment taskmanager -n taskmanager --replicas=0
  echo "    cluster1 taskmanager scaled to 0"
fi

echo "==> Step 3: Create final archive backup on cluster1"
if [ "$DRY_RUN" != "true" ]; then
  ARCHIVE_NAME="archive-$(date +%Y%m%d-%H%M%S)"
  velero backup create "$ARCHIVE_NAME" \
    --include-namespaces taskmanager \
    --snapshot-volumes=true \
    --wait
  echo "    Archive backup created: $ARCHIVE_NAME"
fi

echo ""
echo "============================================================"
echo "  CUTOVER COMPLETE"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Monitor cluster2 for 24 hours"
echo "  2. Once satisfied, run: terraform destroy in infra/cluster1/"
echo "  3. Delete RDS deletion protection before destroying cluster1"
