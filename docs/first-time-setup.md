# First-Time Setup

This guide covers everything needed to go from a fresh clone to a running GKE cluster in GCP.

---

## Prerequisites

| Tool | Minimum version | Install |
|------|----------------|---------|
| Terraform | 1.5 | `brew install terraform` |
| tflint | latest | `brew install tflint` |
| terraform-docs | latest | `brew install terraform-docs` |
| yq | latest | `brew install yq` |
| gcloud CLI | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |

Verify:

```bash
terraform version
tflint --version
gcloud version
yq --version
```

---

## Step 1 — Authenticate to GCP

```bash
gcloud auth login
gcloud config set project project-ec2467ed-84cd-4898-b5b
gcloud auth application-default login
```

Verify access:

```bash
gcloud projects describe project-ec2467ed-84cd-4898-b5b
```

---

## Step 2 — Enable required GCP APIs

Run once per project:

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  iamcredentials.googleapis.com \
  --project=project-ec2467ed-84cd-4898-b5b
```

---

## Step 3 — Bootstrap the Terraform state bucket

The GCS bucket for remote state must exist before `terraform init` can configure the backend.

```bash
./scripts/bootstrap-state.sh dev
```

Reads `environments/dev/values.yml` and creates `hippo-cloud-tf-state-dev` in `us-central1` with versioning enabled. Safe to re-run — skips creation if the bucket already exists.

---

## Step 4 — Review `values.yml`

`environments/dev/values.yml` is the single source of truth for all infrastructure settings. Confirm the project ID is correct:

```yaml
gcp:
  project_id: project-ec2467ed-84cd-4898-b5b
  region: us-central1
```

Key settings configured for dev:

| Setting | Value |
|---------|-------|
| Cluster name | `hippo-dev-cluster` |
| Release channel | `REGULAR` |
| Node machine type | `e2-standard-2` |
| Node autoscaling | 1–3 nodes |
| Spot instances | enabled (cost saving) |
| Private nodes | enabled |
| Private endpoint | disabled (kubectl from workstations works) |
| Control plane CIDR | `172.16.0.0/28` |
| VPC | `hippo-dev-vpc` / `10.10.0.0/22` |
| Pods CIDR | `10.20.0.0/18` |
| Services CIDR | `10.30.0.0/20` |

---

## Step 5 — Init, plan, and apply

```bash
make plan-dev    # runs terraform init + plan
make apply-dev   # applies the saved plan
```

Or using scripts directly:

```bash
./scripts/tf-init.sh dev
./scripts/tf-plan.sh dev
./scripts/tf-apply.sh dev
```

Expected output on first apply: VPC, subnet, Cloud NAT, GKE cluster, node pool, IAM service accounts, and Workload Identity bindings are created.

---

## Step 6 — Configure kubectl

After apply, retrieve the kubeconfig command from outputs:

```bash
terraform -chdir=environments/dev output kubeconfig_command
```

Run the printed command:

```bash
gcloud container clusters get-credentials hippo-dev-cluster \
  --zone us-central1-a \
  --project project-ec2467ed-84cd-4898-b5b
```

Verify:

```bash
kubectl get nodes
```

---

## Step 7 — Review Workload Identity configuration

`environments/dev/wif.yml` is the single source of truth for all WIF bindings. It has two sections:

**`workloads`** — in-cluster K8s ServiceAccount → GCP SA bindings:

```yaml
workloads:
  - name: frontend-web
    k8s_namespace: default
    k8s_service_account: frontend-web
    gcp_roles:
      - roles/storage.objectViewer
```

To add an in-cluster workload, append an entry here and re-run `make apply-dev`. After apply, get the annotation for the K8s ServiceAccount:

```bash
terraform -chdir=environments/dev output wi_k8s_annotations
```

Apply it to the workload's K8s ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend-web
  namespace: default
  annotations:
    iam.gke.io/gcp-service-account: <value from output above>
```

```bash
kubectl apply -f serviceaccount.yaml
kubectl describe serviceaccount frontend-web -n default
```

**`github_ci`** — GitHub Actions repo → GCP SA bindings (no K8s SA involved):

```yaml
github_ci:
  - name: hippo-helm-publisher
    github_repo: mosavani/hippo_k8s-service
    gcp_roles:
      - roles/artifactregistry.writer
```

To add a CI binding for another repo, append an entry here and re-run `make apply-dev`. Get the SA email for the GitHub secret:

```bash
terraform -chdir=environments/dev output github_ci_service_accounts
```

No `.tf` changes are needed for either section.

---

## Local developer workflow

```bash
make fmt          # format all Terraform files in-place
make lint         # run tflint against modules and environments
make validate     # validate syntax (no cloud credentials needed)
make plan-dev     # init + plan dev
make apply-dev    # apply dev (uses saved plan)
make docs         # regenerate MODULE.md for all modules
```

---

## ArgoCD GAR key (one-time manual step)

The org policy `constraints/iam.disableServiceAccountKeyCreation` blocks Terraform from
creating SA keys. After `make apply-dev`, create and upload the key manually:

```bash
# 1. Create the key locally
gcloud iam service-accounts keys create /tmp/argocd-gar-key.json \
  --iam-account=hippo-dev-cluster-argocd-gar@project-ec2467ed-84cd-4898-b5b.iam.gserviceaccount.com

# 2. Upload it to Secret Manager (Terraform creates the secret, you populate it)
gcloud secrets versions add hippo-dev-cluster-argocd-gar-key \
  --data-file=/tmp/argocd-gar-key.json \
  --project=project-ec2467ed-84cd-4898-b5b

# 3. Shred the local copy immediately
shred -u /tmp/argocd-gar-key.json
```

ESO then syncs the secret into the `argocd` namespace. ArgoCD uses it as a repository
credential with:
- **username**: `_json_key`
- **password**: the full JSON content of the key file

> This only needs to be repeated if the key is rotated. Keys do not expire automatically
> but should be rotated periodically. To rotate: delete the old key version in Secret Manager,
> create a new key with the same commands above, and add a new secret version.

---

## What gets provisioned

| Resource | Name | Notes |
|----------|------|-------|
| VPC | `hippo-dev-vpc` | Custom subnets, regional routing |
| Subnet | `hippo-dev-subnet` | `10.10.0.0/22` |
| Cloud Router | `hippo-dev-vpc-router` | Required for NAT |
| Cloud NAT | `hippo-dev-vpc-nat` | AUTO_ONLY IPs |
| GKE cluster | `hippo-dev-cluster` | Private nodes, REGULAR release channel |
| Node pool | `default-pool` | `e2-standard-2`, 1–3 spot nodes |
| Node SA | `hippo-dev-cluster-nodes` | Least-privilege roles only |
| Workload SA | `hippo-dev-cluster-frontend-web` | Bound to `default/frontend-web` K8s SA |
| CI SA | `hippo-dev-cluster-hippo-helm-publisher` | Bound to `mosavani/hippo_k8s-service` GitHub repo via WIF |
