#!/usr/bin/env bash
# tf-init.sh — Initialize Terraform with GCS backend config read from values.yml
# Usage: ./scripts/tf-init.sh <environment>
# Example: ./scripts/tf-init.sh dev
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment>}"
ENV_DIR="environments/${ENVIRONMENT}"
CONFIG="${ENV_DIR}/values.yml"

if [[ ! -f "${CONFIG}" ]]; then
  echo "ERROR: config not found at ${CONFIG}" >&2
  exit 1
fi

# Parse YAML with yq (install: brew install yq / apt-get install yq)
BUCKET=$(yq '.state.bucket' "${CONFIG}")
PREFIX=$(yq '.state.prefix' "${CONFIG}")
PROJECT=$(yq '.gcp.project_id' "${CONFIG}")

echo "Initializing Terraform for environment: ${ENVIRONMENT}"
echo "  GCS bucket : ${BUCKET}"
echo "  State prefix: ${PREFIX}"
echo "  GCP project : ${PROJECT}"

terraform -chdir="${ENV_DIR}" init \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="prefix=${PREFIX}"
