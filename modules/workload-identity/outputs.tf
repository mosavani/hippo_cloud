output "gcp_service_account_email" {
  description = "Email of the GCP SA — use this in the K8s ServiceAccount annotation"
  value       = google_service_account.workload.email
}

output "gcp_service_account_id" {
  description = "Resource ID of the GCP SA"
  value       = google_service_account.workload.id
}

# Emits the exact annotation the K8s ServiceAccount needs.
# Paste this into your Helm values or K8s manifest.
output "k8s_annotation" {
  description = "Annotation to add to the Kubernetes ServiceAccount"
  value       = "iam.gke.io/gcp-service-account: ${google_service_account.workload.email}"
}
