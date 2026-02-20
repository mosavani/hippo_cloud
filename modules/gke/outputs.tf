output "cluster_id" {
  description = "GKE cluster resource ID"
  value       = google_container_cluster.primary.id
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate authority of the cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_self_link" {
  description = "Server-defined URL for the cluster resource"
  value       = google_container_cluster.primary.self_link
}

output "node_pool_names" {
  description = "Names of all managed node pools"
  value       = [for pool in google_container_node_pool.pools : pool.name]
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = var.enable_workload_identity ? "${var.project_id}.svc.id.goog" : null
}

output "master_version" {
  description = "Current master Kubernetes server version"
  value       = google_container_cluster.primary.master_version
}
