variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name — used to scope the SA name"
}

variable "workload_name" {
  type        = string
  description = "Short name for the workload (e.g. 'api', 'worker'). Used to name the GCP SA."
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace the workload runs in"
}

variable "k8s_service_account" {
  type        = string
  description = "Kubernetes ServiceAccount name that will impersonate the GCP SA"
}

variable "gcp_roles" {
  type        = list(string)
  description = "List of IAM roles to grant the workload GCP SA (e.g. 'roles/storage.objectViewer')"
  default     = []
}
