output "node_service_account_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.gke_nodes.email
}

output "node_service_account_id" {
  description = "Resource ID of the GKE node service account"
  value       = google_service_account.gke_nodes.id
}
