locals {
  # Infrastructure config — cluster, networking, GCP project settings
  config = yamldecode(file("${path.module}/values.yml"))

  # Workload Identity config — one entry per workload needing GCP API access
  wif = yamldecode(file("${path.module}/wif.yml"))

  # Flatten YAML structure into typed locals for readability and validation
  project_id   = local.config.gcp.project_id
  region       = local.config.gcp.region
  environment  = local.config.environment
  cluster_name = local.config.cluster.name
  tags         = local.config.tags
}

# -----------------------------------------------------------------------
# Networking: VPC, Subnet, Cloud NAT
# -----------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  project_id    = local.project_id
  region        = local.region
  network_name  = local.config.networking.network_name
  subnet_name   = local.config.networking.subnet_name
  subnet_cidr   = local.config.networking.subnet_cidr
  pods_cidr     = local.config.networking.pods_cidr
  services_cidr = local.config.networking.services_cidr
}

# -----------------------------------------------------------------------
# IAM: Least-privilege service accounts for nodes and workloads
# -----------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  project_id   = local.project_id
  environment  = local.environment
  cluster_name = local.cluster_name
}

# -----------------------------------------------------------------------
# GKE Cluster
# Node pool configuration comes from YAML via yamlencode/yamldecode so
# the YAML remains the canonical config and Terraform just interprets it.
# -----------------------------------------------------------------------
module "gke" {
  source = "../../modules/gke"

  project_id   = local.project_id
  location     = local.config.cluster.location
  environment  = local.environment
  cluster_name = local.cluster_name
  tags         = local.tags

  network    = module.networking.network_self_link
  subnetwork = module.networking.subnet_self_link

  pods_ip_cidr_range     = module.networking.pods_ip_range_name
  services_ip_cidr_range = module.networking.services_ip_range_name

  master_ipv4_cidr_block  = local.config.cluster.master_ipv4_cidr_block
  enable_private_nodes    = local.config.cluster.enable_private_nodes
  enable_private_endpoint = local.config.cluster.enable_private_endpoint
  deletion_protection     = local.config.cluster.deletion_protection

  master_authorized_networks = [
    for net in local.config.cluster.master_authorized_networks : {
      cidr_block   = net.cidr_block
      display_name = net.display_name
    }
  ]

  release_channel = local.config.cluster.release_channel

  # Node pools: loaded from YAML and passed through yamlencode → yamldecode
  # to guarantee the YAML structure matches the module's variable type.
  node_pools = yamldecode(yamlencode(local.config.cluster.node_pools))

  enable_workload_identity = true
  enable_shielded_nodes    = true

  depends_on = [module.networking, module.iam]
}

# -----------------------------------------------------------------------
# Workload Identity: driven entirely by wif.yml.
# To add a new in-cluster workload, add an entry under wif.yml `workloads`.
# To add a GitHub Actions CI binding, add an entry under wif.yml `github_ci`.
# No Terraform changes needed in either case.
# -----------------------------------------------------------------------

locals {
  wif_pool_id = "projects/68730226170/locations/global/workloadIdentityPools/github-pool"
}

module "workload_identity" {
  source   = "../../modules/workload-identity"
  for_each = { for w in local.wif.workloads : w.name => w }

  project_id          = local.project_id
  environment         = local.environment
  cluster_name        = local.cluster_name
  workload_name       = each.value.name
  k8s_namespace       = each.value.k8s_namespace
  k8s_service_account = each.value.k8s_service_account
  gcp_roles           = each.value.gcp_roles

  depends_on = [module.gke]
}

module "github_ci_wif" {
  source   = "../../modules/workload-identity"
  for_each = { for g in local.wif.github_ci : g.name => g }

  project_id                = local.project_id
  environment               = local.environment
  cluster_name              = local.cluster_name
  workload_name             = each.value.name
  github_repo               = each.value.github_repo
  workload_identity_pool_id = local.wif_pool_id
  gcp_roles                 = each.value.gcp_roles

  # github_ci entries don't use K8s SA fields — provide empty defaults
  k8s_namespace       = ""
  k8s_service_account = ""
}
