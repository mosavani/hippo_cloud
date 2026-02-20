#!/usr/bin/env bash
# tf-apply.sh — Apply a pre-generated plan for a given environment
# Usage: ./scripts/tf-apply.sh <environment>
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment>}"
ENV_DIR="environments/${ENVIRONMENT}"
PLAN_FILE="${ENV_DIR}/${ENVIRONMENT}.tfplan"

if [[ ! -f "${PLAN_FILE}" ]]; then
  echo "ERROR: Plan file not found at ${PLAN_FILE}. Run tf-plan.sh first." >&2
  exit 1
fi

echo "Applying Terraform plan for environment: ${ENVIRONMENT}"
terraform -chdir="${ENV_DIR}" apply "${ENVIRONMENT}.tfplan"
