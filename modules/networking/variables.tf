variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
}

variable "network_name" {
  type        = string
  description = "Name of the VPC network"
}

variable "subnet_name" {
  type        = string
  description = "Name of the primary subnet"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR range for the primary subnet"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary CIDR range for GKE pods"
}

variable "services_cidr" {
  type        = string
  description = "Secondary CIDR range for GKE services"
}

