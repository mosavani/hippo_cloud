# First-Time Setup

This guide covers everything needed to go from a fresh clone to a running GKE cluster in GCP.

---

## Prerequisites

Install the following tools before proceeding:

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

## GCP project details

| Field | Value |
|-------|-------|
| Project ID | `hippo-sre-demo` |
| Project number | `68730226170` |
| Default region | `us-central1` |

---

## Step 1 — Authenticate to GCP

```bash
gcloud auth login
gcloud config set project hippo-sre-demo
gcloud auth application-default login
```

Verify access:

```bash
gcloud projects describe hippo-sre-demo
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
  --project=hippo-sre-demo
```

---

## Step 3 — Bootstrap the Terraform state bucket

The GCS bucket for remote state must exist before `terraform init` can configure the backend.

```bash
./scripts/bootstrap-state.sh dev
```

This script reads `environments/dev/values.yml` and creates the bucket `hippo-cloud-tf-state-dev` in `us-central1` with versioning enabled. Safe to re-run — skips creation if the bucket already exists.

---

## Step 4 — Review `values.yml`

`environments/dev/values.yml` is the single source of truth for all infrastructure settings. Confirm the project ID is set correctly:

```yaml
gcp:
  project_id: hippo-sre-demo
  region: us-central1
```

Key settings already configured for dev:

| Setting | Value |
|---------|-------|
| Cluster name | `hippo-dev-cluster` |
| Release channel | `REGULAR` |
| Node machine type | `e2-standard-4` |
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

Run the printed command, for example:

```bash
gcloud container clusters get-credentials hippo-dev-cluster \
  --region us-central1 \
  --project project-ec2467ed-84cd-4898-b5b
```

Verify:

```bash
kubectl get nodes
```

---

## Step 7 — Review Workload Identity configuration

`environments/dev/wif.yml` defines which Kubernetes workloads get GCP IAM access. The default entry:

```yaml
workloads:
  - name: frontend-web
    k8s_namespace: default
    k8s_service_account: frontend-web
    gcp_roles:
      - roles/storage.objectViewer
```

To add a workload, append an entry to this file and re-run `make apply-dev`. No `.tf` changes needed.

After apply, get the annotation value for each workload's Kubernetes ServiceAccount:

```bash
terraform -chdir=environments/dev output wi_k8s_annotations
```

Apply that annotation to the workload's K8s ServiceAccount manifest as <your-serviceaccount-file>.yaml:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api
  namespace: default
  annotations:
    iam.gke.io/gcp-service-account: <value from output above>
```

```

  kubectl apply -f <your-serviceaccount-file>.yaml

  Verify the annotation is set:

  kubectl describe serviceaccount frontend-web -n default

  Any pod that uses serviceAccountName: frontend-web in its spec will then automatically get a token that impersonates the GCP SA, giving it roles/storage.objectViewer without any key files.

````
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

## What gets provisioned

| Resource | Name | Notes |
|----------|------|-------|
| VPC | `hippo-dev-vpc` | Custom subnets, regional routing |
| Subnet | `hippo-dev-subnet` | `10.10.0.0/22`, flow logs enabled |
| Cloud Router | `hippo-dev-vpc-router` | Required for NAT |
| Cloud NAT | `hippo-dev-vpc-nat` | AUTO_ONLY IPs, error logging |
| GKE cluster | `hippo-dev-cluster` | Private nodes, REGULAR release channel |
| Node pool | `default-pool` | `e2-standard-4`, 1–3 spot nodes |
| Node SA | `hippo-dev-cluster-nodes` | Least-privilege roles only |
| Workload SA | `hippo-dev-cluster-api` | Bound to `default/api` K8s SA |
