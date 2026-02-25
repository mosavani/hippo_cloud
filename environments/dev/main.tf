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
  terraform_sa = "ci-terraform@project-ec2467ed-84cd-4898-b5b.iam.gserviceaccount.com"
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

# -----------------------------------------------------------------------
# ArgoCD GAR: dedicated SA + Secret Manager secret.
#
# The SA key is created MANUALLY (org policy blocks Terraform key creation):
#   gcloud iam service-accounts keys create /tmp/argocd-gar-key.json \
#     --iam-account=hippo-dev-cluster-argocd-gar@project-ec2467ed-84cd-4898-b5b.iam.gserviceaccount.com
#   gcloud secrets versions add hippo-dev-cluster-argocd-gar-key \
#     --data-file=/tmp/argocd-gar-key.json \
#     --project=project-ec2467ed-84cd-4898-b5b
#   shred -u /tmp/argocd-gar-key.json
#
# ESO reads the key from Secret Manager and syncs it into the argocd namespace.
# ArgoCD uses username=_json_key, password=<full JSON key> to auth to GAR OCI.
# -----------------------------------------------------------------------
resource "google_service_account" "argocd_gar" {
  project      = local.project_id
  account_id   = trimsuffix(substr(join("-", [local.cluster_name, "argocd-gar"]), 0, 30), "-")
  display_name = "ArgoCD GAR reader (${local.environment})"
  description  = "ArgoCD repo-server: pulls Helm charts from GAR via _json_key Basic Auth"
}

resource "google_project_iam_member" "argocd_gar_reader" {
  project = local.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.argocd_gar.email}"
}

resource "google_secret_manager_secret" "argocd_gar_key" {
  project   = local.project_id
  secret_id = "${local.cluster_name}-argocd-gar-key"

  replication {
    auto {}
  }

  labels = {
    environment = local.environment
    managed-by  = "terraform"
    component   = "argocd"
  }
}

# Grant ESO's GCP SA access to read this specific secret.
resource "google_secret_manager_secret_iam_member" "eso_argocd_gar_accessor" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.argocd_gar_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.workload_identity["eso"].gcp_service_account_email}"
}

module "github_ci_wif" {
  source   = "../../modules/workload-identity"
  for_each = { for g in local.wif.github_ci : g.name => g }

  project_id                = local.project_id
  environment               = local.environment
  cluster_name              = local.cluster_name
  workload_name             = each.value.name
  github_repo               = try(each.value.github_repo, "")
  github_org                = try(each.value.github_org, "")
  workload_identity_pool_id = local.wif_pool_id
  gcp_roles                 = each.value.gcp_roles

  # github_ci entries don't use K8s SA fields — provide empty defaults
  k8s_namespace       = ""
  k8s_service_account = ""
}
