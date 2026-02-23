# GCP service account for the workload.
# account_id must be 6-30 chars and cannot start or end with a hyphen.
# Truncate to 30 chars then strip any trailing hyphens.
locals {
  account_id = trimsuffix(substr("${var.cluster_name}-${var.workload_name}", 0, 30), "-")
}

resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = local.account_id
  display_name = "${var.workload_name} (${var.environment})"
  description  = "Workload Identity SA for ${var.workload_name} running in ${var.k8s_namespace}/${var.k8s_service_account}"
}

# Grant the GCP SA whatever project-level roles the workload needs.
# Caller passes the list via var.gcp_roles — this module stays generic.
resource "google_project_iam_member" "workload_roles" {
  for_each = toset(var.gcp_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workload.email}"
}

# K8s SA binding: allows a specific K8s ServiceAccount in a specific namespace
# to impersonate the GCP SA. Used for in-cluster workloads.
# Only created when github_repo is not set.
resource "google_service_account_iam_member" "workload_identity_binding" {
  count = var.github_repo == "" ? 1 : 0

  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
}

# GitHub Actions binding — per-repo: allows any job in the specified repo
# to impersonate the GCP SA via WIF.
resource "google_service_account_iam_member" "github_actions_binding_repo" {
  count = var.github_repo != "" ? 1 : 0

  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.workload_identity_pool_id}/attribute.repository/${var.github_repo}"
}

# GitHub Actions binding — per-org: allows any job in ANY repo under the org
# to impersonate the GCP SA via WIF.
resource "google_service_account_iam_member" "github_actions_binding_org" {
  count = var.github_org != "" ? 1 : 0

  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.workload_identity_pool_id}/attribute.repository_owner/${var.github_org}"
}
