# Remote state stored in GCS.
# The bucket and prefix come from values.yaml but cannot use locals here
# (Terraform backend config must be static). Use -backend-config flags or
# the init wrapper script (scripts/tf-init.sh) to pass these values.
#
# Usage:
#   terraform init \
#     -backend-config="bucket=$(yq .state.bucket config.yaml)" \
#     -backend-config="prefix=$(yq .state.prefix config.yaml)"
#
# Or use scripts/tf-init.sh which reads config.yaml automatically.
terraform {
  backend "gcs" {
    # Values injected at `terraform init` time via -backend-config
    # bucket = <from config.yaml: state.bucket>
    # prefix = <from config.yaml: state.prefix>
  }
}
