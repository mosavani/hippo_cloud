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

variable "terraform_sa" {
  type        = string
  description = "Email of the SA running Terraform (granted iam.serviceAccountUser on the node SA to allow attaching it to node pools)"
}
