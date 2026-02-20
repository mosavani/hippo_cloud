#!/usr/bin/env bash
# tf-plan.sh — Run terraform plan for a given environment
# Usage: ./scripts/tf-plan.sh <environment>
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment>}"
ENV_DIR="environments/${ENVIRONMENT}"

echo "Planning Terraform for environment: ${ENVIRONMENT}"
terraform -chdir="${ENV_DIR}" plan -out="${ENVIRONMENT}.tfplan"
