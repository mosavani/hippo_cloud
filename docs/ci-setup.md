# CI Setup — GitHub Actions with Workload Identity Federation

The CI pipeline runs on GitHub Actions and authenticates to GCP using **Workload Identity Federation (WIF)** — no long-lived service account keys are stored anywhere.

GitHub org/repo: `mosavani/hippo_cloud`
GCP project: `project-ec2467ed-84cd-4898-b5b` (number: `68730226170`)

---

## How the pipeline works

```
PR opened → main
  ├── fmt check    (fails fast if any file is unformatted)
  ├── tflint       (Google ruleset, modules + environments)
  ├── validate     (syntax check, no cloud credentials needed)
  └── plan         (authenticates via WIF, posts output as PR comment)

Push to main (PR merged)
  ├── fmt check
  ├── tflint
  ├── validate
  └── apply-dev    (authenticates via WIF, terraform apply -auto-approve)
```

The pipeline only triggers when files under `environments/**` or `modules/**` change (or the workflow file itself).

---

## One-time GCP setup

### Step 1 — Create a CI service account

```bash
gcloud iam service-accounts create ci-terraform \
  --display-name="GitHub Actions Terraform CI" \
  --project=project-ec2467ed-84cd-4898-b5b
```

Grant it the permissions Terraform needs:

```bash
for role in \
  roles/container.admin \
  roles/compute.networkAdmin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountKeyAdmin \
  roles/resourcemanager.projectIamAdmin \
  roles/storage.admin; do
  gcloud projects add-iam-policy-binding project-ec2467ed-84cd-4898-b5b \
    --member="serviceAccount:ci-terraform@project-ec2467ed-84cd-4898-b5b.iam.gserviceaccount.com" \
    --role="${role}"
done
```

> Scope these roles further once the project stabilizes. `resourcemanager.projectIamAdmin` is needed for IAM bindings in `modules/iam` and `modules/workload-identity`.

---

### Step 2 — Create a Workload Identity pool

```bash
gcloud iam workload-identity-pools create "github-pool" \
  --project=project-ec2467ed-84cd-4898-b5b \
  --location=global \
  --display-name="GitHub Actions Pool"
```

---

### Step 3 — Create a GitHub OIDC provider

```bash
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project=project-ec2467ed-84cd-4898-b5b \
  --location=global \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner=='mosavani'"
```

The `--attribute-condition` locks this provider to any repo under the `mosavani` org. To add a new repo that needs GCP access, no provider changes are needed — just bind its service account (Step 4) and set the secrets in that repo.

---

### Step 4 — Allow the GitHub repo to impersonate the CI SA

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "ci-terraform@project-ec2467ed-84cd-4898-b5b.iam.gserviceaccount.com" \
  --project=project-ec2467ed-84cd-4898-b5b \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/68730226170/locations/global/workloadIdentityPools/github-pool/attribute.repository/mosavani/hippo_cloud"
```

---

### Step 5 — Grant CI SA access to the state bucket

```bash
gcloud storage buckets add-iam-policy-binding gs://hippo-cloud-tf-state-dev \
  --member="serviceAccount:ci-terraform@project-ec2467ed-84cd-4898-b5b.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

---

## GitHub repository secrets

Set these in **Settings → Secrets and variables → Actions → New repository secret**:

| Secret name | Value |
|-------------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/68730226170/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | `ci-terraform@project-ec2467ed-84cd-4898-b5b.iam.gserviceaccount.com` |
| `TF_STATE_BUCKET_DEV` | `hippo-cloud-tf-state-dev` |

Get the provider resource name from GCP if needed:

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --workload-identity-pool=github-pool \
  --location=global \
  --project=project-ec2467ed-84cd-4898-b5b \
  --format="value(name)"
```

---

## GitHub Actions environment (optional but recommended)

Create a GitHub environment named `dev` to add required reviewers or deployment protection rules before the apply job runs.

Go to **Settings → Environments → New environment → `dev`**.

The `apply-dev` job in `.github/workflows/terraform-ci.yml` already references `environment: dev`:

```yaml
apply-dev:
  environment:
    name: dev
    url: https://console.cloud.google.com/kubernetes
```

---

## Verifying the pipeline

1. Open a pull request against `main` that touches a file under `environments/` or `modules/`.
2. All four jobs (`fmt`, `lint`, `validate`, `plan`) should appear in the PR checks.
3. The `plan` job posts a comment to the PR with the Terraform plan output.
4. Merge the PR. The `apply-dev` job runs automatically.

Check workflow runs at:
`https://github.com/mosavani/hippo_cloud/actions`

---

## Pipeline permissions

The workflow sets these GitHub token permissions:

```yaml
permissions:
  contents: read       # checkout the repo
  id-token: write      # exchange OIDC token for GCP access token (WIF)
  pull-requests: write # post plan output as PR comment
```

These are the minimum permissions required. No other GitHub token scopes are used.

---

## Granting CI access to other repos

Any GitHub repo that needs GCP access (e.g. `hippo_k8s-service` publishing Helm charts to GAR) uses the same WIF pool. Add an entry to `environments/dev/wif.yml` under `github_ci`:

```yaml
github_ci:
  - name: hippo-helm-publisher
    github_repo: mosavani/hippo_k8s-service
    gcp_roles:
      - roles/artifactregistry.writer
```

Then apply:

```bash
make apply-dev
terraform -chdir=environments/dev output github_ci_service_accounts
```

Set `GCP_SERVICE_ACCOUNT` in the target repo to the printed SA email. The `GCP_WORKLOAD_IDENTITY_PROVIDER` value is the same as this repo — no new pool or provider needed.

---

## What Workload Identity Federation replaces

Without WIF, you would need to:
- Create a service account JSON key.
- Store it as a GitHub secret.
- Rotate it regularly.
- Risk exposure if the secret leaks.

With WIF:
- GitHub's OIDC provider issues a short-lived token per workflow run.
- GCP exchanges that token for a temporary access token scoped to the CI SA.
- No key file exists anywhere.
- Token lifetime is bound to the job run.