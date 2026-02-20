output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnet_name" {
  description = "Name of the primary subnet"
  value       = google_compute_subnetwork.primary.name
}

output "subnet_self_link" {
  description = "Self-link of the primary subnet"
  value       = google_compute_subnetwork.primary.self_link
}

output "pods_ip_range_name" {
  description = "Name of the secondary IP range for pods"
  value       = "${var.subnet_name}-pods"
}

output "services_ip_range_name" {
  description = "Name of the secondary IP range for services"
  value       = "${var.subnet_name}-services"
}
