#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Terraform Backend (S3)
#
# Creates the S3 bucket for Terraform state storage. Concurrency control is
# handled by the CI/CD pipeline (GitHub Actions `concurrency` key), so no
# DynamoDB lock table is needed.
#
# Usage:
#   ./bootstrap.sh
#   cd terraform && terraform init
#
# If you need DynamoDB locking later (e.g. multiple pipelines), run:
#   aws dynamodb create-table \
#     --table-name blog-terraform-locks \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST
# Then uncomment `dynamodb_table` in terraform/main.tf

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TEMPLATE="$TF_DIR/main.tf.template"
MAIN_TF="$TF_DIR/main.tf"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${1:-blog-terraform-state-${ACCOUNT_ID}-us-east-1-an}"
REGION="${2:-us-east-1}"

echo "Bucket s3://${BUCKET} will be created in ${REGION}."

# S3 bucket ──────────────────────────────────────────────────────────────
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket already exists: ${BUCKET}. Bootstrap has already been done."
else
  echo "Creating bucket: ${BUCKET}."

  # The -an suffix means account-regional namespace bucket, which requires
  # the x-amz-bucket-namespace header. Using s3api create-bucket with the
  # --bucket-namespace flag satisfies this requirement.
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --bucket-namespace "account-regional"

  echo "Creation successful. Bucket configuration will be done now."

  # Versioning - required for state recovery
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled

  # Block public access - state files can contain sensitive values
  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  # Default encryption
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

  echo "Configuration successful."
fi

# Generate terraform/main.tf from template ────────────────────────────
if [ -f "$TEMPLATE" ]; then
  cp "$TEMPLATE" "$MAIN_TF"
  sed -i "s/ACCOUNTID/$ACCOUNT_ID/g" "$MAIN_TF"
  echo "Generated terraform/main.tf with account ID: ${ACCOUNT_ID}"
else
  echo ""
  echo "WARNING: template not found at ${TEMPLATE}."
  echo "Run this script from the project root directory."
fi

echo ""
echo "Done! Now run:"
echo "  cd terraform && terraform init"
