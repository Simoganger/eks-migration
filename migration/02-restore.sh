#!/usr/bin/env bash
# Restore a Velero backup to cluster2.
# Usage: BACKUP_NAME=pre-migration DRY_RUN=false ./02-restore.sh
set -euo pipefail

BACKUP_NAME="${BACKUP_NAME:-pre-migration}"
DRY_RUN="${DRY_RUN:-false}"
CONTEXT="${CLUSTER2_CONTEXT:-cluster2}"
RESTORE_NAME="${BACKUP_NAME}-restore-$(date +%s)"

echo "==> Switching to cluster2 context: $CONTEXT"
kubectl config use-context "$CONTEXT"

echo "==> Velero status on cluster2"
velero backup-location get

echo "==> Waiting for backup '$BACKUP_NAME' to be visible in cluster2..."
for i in {1..12}; do
  if velero backup get "$BACKUP_NAME" &>/dev/null; then
    break
  fi
  echo "  Waiting ($i/12)..."
  sleep 10
done

if [ "$DRY_RUN" = "true" ]; then
  echo "[DRY RUN] Would restore backup '$BACKUP_NAME' as '$RESTORE_NAME'"
  exit 0
fi

echo "==> Restoring backup '$BACKUP_NAME' → restore '$RESTORE_NAME'"
velero restore create "$RESTORE_NAME" \
  --from-backup "$BACKUP_NAME" \
  --include-namespaces taskmanager \
  --wait

echo "==> Restore status:"
velero restore describe "$RESTORE_NAME" --details

STATUS=$(velero restore get "$RESTORE_NAME" -o json | jq -r '.status.phase')
if [ "$STATUS" != "Completed" ]; then
  echo "ERROR: Restore phase is '$STATUS' — expected 'Completed'"
  exit 1
fi

echo "==> Restore '$RESTORE_NAME' completed. Checking pods..."
kubectl get pods -n taskmanager
echo ""
echo "==> Verify the app on cluster2 before shifting traffic."
