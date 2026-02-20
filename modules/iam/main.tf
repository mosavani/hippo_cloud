# Dedicated GKE node service account following principle of least privilege.
# Nodes use this SA instead of the default compute SA (which has broad access).
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE Node SA for ${var.cluster_name} (${var.environment})"
  description  = "Least-privilege service account for GKE nodes in ${var.environment}"
}

# Minimal roles required for GKE nodes
locals {
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/storage.objectViewer",         # Pull container images from GCR/AR
    "roles/artifactregistry.reader",      # Pull from Artifact Registry
  ]
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
