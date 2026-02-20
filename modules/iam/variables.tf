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
  description = "GKE cluster name (used for SA naming)"
}
