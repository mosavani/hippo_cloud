terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0, < 6.0"
    }
  }
}

provider "google" {
  project = yamldecode(file("${path.module}/values.yml")).gcp.project_id
  region  = yamldecode(file("${path.module}/values.yml")).gcp.region
}

provider "google-beta" {
  project = yamldecode(file("${path.module}/values.yml")).gcp.project_id
  region  = yamldecode(file("${path.module}/values.yml")).gcp.region
}
