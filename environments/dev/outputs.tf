output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "GKE cluster region"
  value       = module.gke.cluster_location
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint (sensitive)"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (sensitive)"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "node_service_account" {
  description = "Node service account email"
  value       = module.iam.node_service_account_email
}

output "network_name" {
  description = "VPC network name"
  value       = module.networking.network_name
}

output "subnet_name" {
  description = "Primary subnet name"
  value       = module.networking.subnet_name
}

# Workload Identity annotations — paste into K8s ServiceAccount manifests
# Key is the workload name as defined in wif.yml
output "wi_k8s_annotations" {
  description = "Annotations for each workload K8s ServiceAccount, keyed by workload name"
  value       = { for name, mod in module.workload_identity : name => mod.k8s_annotation }
}

# Convenience: kubeconfig instructions
output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${module.gke.cluster_location} --project ${yamldecode(file("${path.module}/values.yml")).gcp.project_id}"
}
