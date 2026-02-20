# hippo_cloud

Standard GKE cluster provisioned with Terraform — reusable modules, YAML-driven configuration, GCS remote state, and GitHub Actions CI.

---

## Repository layout

```
hippo_cloud/
├── modules/
│   ├── gke/                # GKE cluster + node pools
│   ├── networking/         # VPC, subnet, Cloud NAT
│   ├── iam/                # Least-privilege node service account
│   └── workload-identity/  # Reusable WIF SA + binding per workload
├── environments/
│   └── dev/
│       ├── values.yml  ← infrastructure config (project, cluster, networking)
│       ├── wif.yml     ← workload identity config (one entry per workload)
│       ├── main.tf     ← calls all modules; reads values.yml and wif.yml
│       ├── backend.tf  ← GCS remote state (bucket injected at init)
│       ├── versions.tf
│       └── outputs.tf
├── scripts/
│   ├── bootstrap-state.sh  # Create GCS state bucket (run once)
│   ├── tf-init.sh          # Init with backend config from values.yml
│   ├── tf-plan.sh          # terraform plan wrapper
│   └── tf-apply.sh         # terraform apply wrapper
├── .github/workflows/
│   └── terraform-ci.yml    # CI: fmt, lint, validate, plan (PR), apply (main)
├── .tflint.hcl             # tflint rules
└── Makefile                # Developer shortcuts
```

---

## Design principles

| Principle | Implementation |
|-----------|---------------|
| **YAML as config** | `values.yml` for infrastructure; `wif.yml` for workload identity. Both loaded via `yamldecode(file(...))`. |
| **Managed remote state** | GCS backend. Bucket versioning enabled — state is always recoverable. |
| **Read-only protection** | `deletion_protection = false` in dev. State bucket versioning prevents un-versioned state. |
| **Modular design** | Each module has `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. |
| **Workload Identity** | `modules/workload-identity` is reusable per workload. Adding a workload = one YAML entry in `wif.yml`, no Terraform changes. |
| **Secrets — no long-lived keys** | CI uses Workload Identity Federation (OIDC). No SA JSON stored anywhere. |
| **Linting** | `terraform fmt` + `tflint` (google ruleset) run on every PR. |
| **CI gates** | fmt → lint → validate → plan (PR comment) → apply (merge to main). |

---

## Prerequisites

| Tool | Install |
|------|---------|
| Terraform ≥ 1.5 | `brew install terraform` |
| tflint | `brew install tflint` |
| terraform-docs | `brew install terraform-docs` |
| yq | `brew install yq` |
| gcloud CLI | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |

---

## First-time setup

### 1. Update `values.yml`

Edit `environments/dev/values.yml` and set your GCP project ID:

```yaml
gcp:
  project_id: your-real-project-id
```

### 2. Bootstrap GCS state bucket

```bash
./scripts/bootstrap-state.sh dev
```

Creates the GCS bucket with versioning enabled. Run once.

### 3. Authenticate

```bash
gcloud auth application-default login
```

### 4. Init + plan + apply

```bash
make plan-dev
make apply-dev
```

---

## Adding a workload

Edit `environments/dev/wif.yml` and add an entry:

```yaml
workloads:
  - name: worker
    k8s_namespace: jobs
    k8s_service_account: worker
    gcp_roles:
      - roles/pubsub.subscriber
```

Then apply. No changes to any `.tf` file needed.

After apply, annotate the Kubernetes ServiceAccount with the value from:

```bash
terraform -chdir=environments/dev output wi_k8s_annotations
```

```yaml
# K8s ServiceAccount (application team's manifest)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: worker
  namespace: jobs
  annotations:
    iam.gke.io/gcp-service-account: <value from output above>
```

---

## GitHub Actions secrets

Set in **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | WIF provider resource name |
| `GCP_SERVICE_ACCOUNT` | SA email CI impersonates |
| `TF_STATE_BUCKET_DEV` | GCS bucket name for dev state |

### Setting up Workload Identity Federation for CI (no SA key needed)

```bash
# 1. Create a WIF pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="YOUR_PROJECT" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# 2. Create a provider for GitHub
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="YOUR_PROJECT" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# 3. Allow the GitHub repo to impersonate the CI SA
gcloud iam service-accounts add-iam-policy-binding "ci-sa@YOUR_PROJECT.iam.gserviceaccount.com" \
  --project="YOUR_PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_ORG/hippo_cloud"
```

Set `GCP_WORKLOAD_IDENTITY_PROVIDER` to:
```
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
```

---

## CI workflow

```
PR opened
  ├── fmt check    (fails fast if unformatted)
  ├── tflint       (modules + environments)
  ├── validate     (dev — no cloud credentials needed)
  └── plan         (dev — output posted as PR comment)

Merge to main
  └── apply        (dev, auto-approve)
```

---

## Local developer workflow

```bash
make fmt        # format all Terraform files
make lint       # run tflint
make plan-dev   # init + plan
make apply-dev  # apply saved plan
make docs       # generate MODULE.md for all modules
```

---

## Secrets management

- **No long-lived credentials in CI** — WIF exchanges a short-lived GitHub OIDC token for a GCP access token.
- **No `.tfvars` with secrets** — all config is in `values.yml` and `wif.yml` (both committed). No sensitive values needed.
- **GCS state encrypted at rest** by default (Google-managed keys).
- **State versioning** means every apply is recoverable.
