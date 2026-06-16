#!/usr/bin/env bash
# Create a Velero backup of the taskmanager namespace on cluster1.
# Usage: BACKUP_NAME=pre-migration DRY_RUN=false ./01-backup.sh
set -euo pipefail

BACKUP_NAME="${BACKUP_NAME:-pre-migration}"
DRY_RUN="${DRY_RUN:-false}"
CONTEXT="${CLUSTER1_CONTEXT:-cluster1}"

echo "==> Switching to cluster1 context: $CONTEXT"
kubectl config use-context "$CONTEXT"

echo "==> Velero status on cluster1"
velero backup-location get

if [ "$DRY_RUN" = "true" ]; then
  echo "[DRY RUN] Would create backup: $BACKUP_NAME"
  exit 0
fi

echo "==> Creating Velero backup: $BACKUP_NAME"
velero backup create "$BACKUP_NAME" \
  --include-namespaces taskmanager \
  --snapshot-volumes=true \
  --wait

echo "==> Backup status:"
velero backup describe "$BACKUP_NAME" --details

STATUS=$(velero backup get "$BACKUP_NAME" -o json | jq -r '.status.phase')
if [ "$STATUS" != "Completed" ]; then
  echo "ERROR: Backup phase is '$STATUS' — expected 'Completed'"
  exit 1
fi

echo "==> Backup '$BACKUP_NAME' completed successfully!"
