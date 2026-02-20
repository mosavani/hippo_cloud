variable "project_id" {
  type        = string
  description = "GCP project ID where the GKE cluster will be created"
}

variable "region" {
  type        = string
  description = "GCP region for the cluster"
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "network" {
  type        = string
  description = "VPC network self-link or name for the cluster"
}

variable "subnetwork" {
  type        = string
  description = "VPC subnetwork self-link or name for the cluster nodes"
}

variable "pods_ip_cidr_range" {
  type        = string
  description = "Secondary IP range name for pods (alias IP)"
}

variable "services_ip_cidr_range" {
  type        = string
  description = "Secondary IP range name for services (alias IP)"
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR block for the private GKE control plane"
  default     = "172.16.0.0/28"
}

variable "enable_private_nodes" {
  type        = bool
  description = "Whether nodes have private IP addresses only"
  default     = true
}

variable "enable_private_endpoint" {
  type        = bool
  description = "Whether the master is accessible only via private IP"
  default     = false
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "List of CIDR blocks allowed to reach the Kubernetes control plane"
  default     = []
}

variable "node_pools" {
  type = map(object({
    machine_type    = string
    min_node_count  = number
    max_node_count  = number
    disk_size_gb    = optional(number, 100)
    disk_type       = optional(string, "pd-standard")
    image_type      = optional(string, "COS_CONTAINERD")
    spot            = optional(bool, false)
    preemptible     = optional(bool, false)
    service_account = optional(string, "")
    oauth_scopes = optional(list(string), [
      "https://www.googleapis.com/auth/cloud-platform"
    ])
    labels = optional(map(string), {})
    tags   = optional(list(string), [])
    node_taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  description = "Map of node pool names to their configuration"
}

variable "release_channel" {
  type        = string
  description = "GKE release channel: RAPID, REGULAR, STABLE, or UNSPECIFIED"
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "UNSPECIFIED"], var.release_channel)
    error_message = "release_channel must be one of: RAPID, REGULAR, STABLE, UNSPECIFIED."
  }
}

variable "enable_workload_identity" {
  type        = bool
  description = "Enable Workload Identity on the cluster"
  default     = true
}

variable "enable_shielded_nodes" {
  type        = bool
  description = "Enable Shielded Nodes features on all nodes in the cluster"
  default     = true
}

variable "deletion_protection" {
  type        = bool
  description = "Whether or not to allow Terraform to destroy the cluster"
  default     = true
}

variable "maintenance_start_time" {
  type        = string
  description = "Start time for the maintenance window (RFC3339 format, e.g. '2024-01-01T02:00:00Z')"
  default     = "2024-01-01T02:00:00Z"
}

variable "maintenance_end_time" {
  type        = string
  description = "End time for the maintenance window (RFC3339 format)"
  default     = "2024-01-01T06:00:00Z"
}

variable "maintenance_recurrence" {
  type        = string
  description = "RFC 5545 RRULE for maintenance windows"
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}

variable "logging_service" {
  type        = string
  description = "Logging service for the cluster. 'logging.googleapis.com/kubernetes' or 'none'"
  default     = "logging.googleapis.com/kubernetes"
}

variable "monitoring_service" {
  type        = string
  description = "Monitoring service for the cluster"
  default     = "monitoring.googleapis.com/kubernetes"
}

variable "tags" {
  type        = map(string)
  description = "Labels to apply to all cluster resources"
  default     = {}
}
