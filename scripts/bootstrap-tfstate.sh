#!/usr/bin/env bash
# Bootstrap the Terraform remote state backend (S3 + DynamoDB).
# Run this ONCE before any other terraform commands.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="${TF_STATE_BUCKET:-eks-migration-tfstate}"
TABLE_NAME="${TF_STATE_LOCK_TABLE:-eks-migration-tfstate-lock}"

echo "==> Bootstrapping Terraform state backend"
echo "    Region:  $AWS_REGION"
echo "    Bucket:  $BUCKET_NAME"
echo "    DynamoDB: $TABLE_NAME"
echo ""

cd "$(dirname "$0")/../infra/bootstrap"

terraform init
terraform apply \
  -var="aws_region=$AWS_REGION" \
  -var="bucket_name=$BUCKET_NAME" \
  -var="dynamodb_table_name=$TABLE_NAME" \
  -auto-approve

echo ""
echo "==> Bootstrap complete!"
echo "    Add these to your GitHub Actions secrets:"
echo "    TF_STATE_BUCKET=$BUCKET_NAME"
echo "    TF_STATE_LOCK_TABLE=$TABLE_NAME"
