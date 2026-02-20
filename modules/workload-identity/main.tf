# GCP service account for the workload.
# Named to make its scope obvious: <cluster>-<workload>
resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-${var.workload_name}"
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

# The WIF binding: allows the specific K8s SA in the specific namespace
# to impersonate the GCP SA. Scoped tightly — not the whole cluster.
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
}
