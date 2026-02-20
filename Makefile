.PHONY: help fmt lint validate plan-dev apply-dev bootstrap-dev docs

# Default target
help:
	@echo "hippo_cloud Terraform targets"
	@echo ""
	@echo "  bootstrap-dev   Create GCS state bucket for dev (run once)"
	@echo "  init-dev        terraform init for dev environment"
	@echo "  plan-dev        terraform plan for dev environment"
	@echo "  apply-dev       terraform apply for dev environment"
	@echo "  fmt             Format all Terraform files recursively"
	@echo "  lint            Run tflint on all modules and environments"
	@echo "  validate        Run terraform validate on dev environment"
	@echo "  docs            Generate terraform-docs MODULE.md for all modules"

# ---- State bootstrap (run once) --------------------------------------

bootstrap-dev:
	@./scripts/bootstrap-state.sh dev

# ---- Terraform lifecycle ---------------------------------------------

init-dev:
	@./scripts/tf-init.sh dev

plan-dev: init-dev
	@./scripts/tf-plan.sh dev

apply-dev: plan-dev
	@./scripts/tf-apply.sh dev

# ---- Code quality ----------------------------------------------------

fmt:
	@terraform fmt -recursive

lint:
	@tflint --recursive

validate: init-dev
	@terraform -chdir=environments/dev validate

docs:
	@for dir in modules/gke modules/networking modules/iam; do \
	  terraform-docs markdown table --output-file MODULE.md $$dir; \
	  echo "Generated $$dir/MODULE.md"; \
	done
