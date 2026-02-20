# CI Setup: GitHub Actions + GCP Workload Identity Federation

The CI pipeline authenticates to GCP using keyless Workload Identity Federation (WIF) — no long-lived service account keys are stored anywhere. This is a one-time bootstrap that must be done before the first CI run.

---

## Prerequisites

- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- GCP project already created (e.g. `hippo-cloud-dev`)
- GitHub repository already created (e.g. `msavani/hippo_cloud`)

---

## Step 1 — Bootstrap WIF infrastructure in GCP

Set your variables:

```bash
PROJECT_ID="hippo-cloud-dev"
REPO="your-github-org/hippo_cloud"   # e.g. msavani/hippo_cloud
```

Create the CI service account:

```bash
gcloud iam service-accounts create github-ci \
  --project=$PROJECT_ID \
  --display-name="GitHub Actions CI"
```

Create the Workload Identity Pool:

```bash
gcloud iam workload-identity-pools create github-pool \
  --project=$PROJECT_ID \
  --location=global \
  --display-name="GitHub Actions Pool"
```

Create the OIDC provider inside the pool:

```bash
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project=$PROJECT_ID \
  --location=global \
  --workload-identity-pool=github-pool \
  --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='${REPO}'"
```

Allow the WIF provider to impersonate the CI service account:

```bash
POOL_ID=$(gcloud iam workload-identity-pools describe github-pool \
  --project=$PROJECT_ID --location=global --format='value(name)')

gcloud iam service-accounts add-iam-policy-binding \
  github-ci@${PROJECT_ID}.iam.gserviceaccount.com \
  --project=$PROJECT_ID \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${REPO}"
```

Grant the CI service account permissions to manage Terraform state and GCP resources:

```bash
# Read/write Terraform state in GCS
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-ci@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Manage GKE, networking, IAM (adjust to least-privilege as needed)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-ci@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/editor"
```

---

## Step 2 — Retrieve values for GitHub Secrets

Run these commands to get the exact strings to paste into GitHub:

```bash
# GCP_WORKLOAD_IDENTITY_PROVIDER
gcloud iam workload-identity-pools providers describe github-provider \
  --project=$PROJECT_ID \
  --location=global \
  --workload-identity-pool=github-pool \
  --format='value(name)'
# Example output:
# projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider

# GCP_SERVICE_ACCOUNT
echo "github-ci@${PROJECT_ID}.iam.gserviceaccount.com"

# TF_STATE_BUCKET_DEV (set when you ran scripts/bootstrap-state.sh)
echo "hippo-cloud-tf-state-dev"
```

---

## Step 3 — Add secrets to GitHub

Go to **GitHub → Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret name                      | Value                                                                 |
|----------------------------------|-----------------------------------------------------------------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full provider resource name from Step 2                               |
| `GCP_SERVICE_ACCOUNT`            | `github-ci@<project-id>.iam.gserviceaccount.com`                     |
| `TF_STATE_BUCKET_DEV`            | GCS bucket name (e.g. `hippo-cloud-tf-state-dev`)                    |

---

## Step 4 — Configure required status checks (PR blocking)

Go to **GitHub → Settings → Branches → Add branch ruleset** (or classic branch protection on `main`) and require these status checks:

- `Format check`
- `tflint`
- `Validate (dev)`
- `Plan (dev)`

This ensures no PR can merge unless all four checks pass.

---

## How it works

```
GitHub Actions job
  │
  ├── Generates a short-lived OIDC token (signed by GitHub)
  │
  └── Exchanges token with GCP Workload Identity Federation
        │
        └── GCP issues a short-lived access token for the CI service account
              │
              └── Terraform uses the token to access GCS state and GCP APIs
```

No service account keys are created or stored. Access is scoped to the specific GitHub repository via the `attribute.condition` on the WIF provider.

---

## Troubleshooting

**`the GitHub Action workflow must specify exactly one of "workload_identity_provider" or "credentials_json"`**

The `GCP_WORKLOAD_IDENTITY_PROVIDER` secret is missing or empty. Verify:
1. The secret exists in GitHub (Settings → Secrets → Actions)
2. The workflow is not triggered from a fork (secrets are not passed to fork PRs by default)
3. The secret value is the full resource name (starts with `projects/`)

**`Permission denied` on GCS bucket during `terraform init`**

The CI service account does not have `roles/storage.admin` (or at least `roles/storage.objectViewer` + `roles/storage.legacyBucketWriter`) on the state bucket. Re-run the `gcloud projects add-iam-policy-binding` command from Step 1.

**`principalSet` binding not working**

Confirm the `REPO` variable matches the exact `owner/repo` string (case-sensitive) as it appears in `github.repository` in the Actions context.
