#!/usr/bin/env bash
# bootstrap-state.sh — Create GCS buckets for Terraform remote state.
# Run ONCE before the first `terraform init`.
# Usage: ./scripts/bootstrap-state.sh <environment>
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment>}"
CONFIG="environments/${ENVIRONMENT}/values.yml"

if [[ ! -f "${CONFIG}" ]]; then
  echo "ERROR: config not found at ${CONFIG}" >&2
  exit 1
fi

BUCKET=$(yq '.state.bucket' "${CONFIG}")
PROJECT=$(yq '.gcp.project_id' "${CONFIG}")
REGION=$(yq '.gcp.region' "${CONFIG}")

echo "Bootstrapping state bucket for environment: ${ENVIRONMENT}"
echo "  Bucket  : ${BUCKET}"
echo "  Project : ${PROJECT}"
echo "  Region  : ${REGION}"

# Create the bucket if it does not already exist
if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT}" &>/dev/null; then
  echo "Bucket gs://${BUCKET} already exists — skipping creation."
else
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT}" \
    --location="${REGION}" \
    --uniform-bucket-level-access

  # Enable versioning — this is the "Read-Only Resources: Prevents un-versioned" guard
  gcloud storage buckets update "gs://${BUCKET}" \
    --versioning

  echo "Bucket gs://${BUCKET} created with versioning enabled."
fi
