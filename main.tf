# =============================================================================
# OSD on GCP - Main Configuration
# =============================================================================
# This is the main entry point for deploying OpenShift Dedicated on GCP
# =============================================================================

terraform {
  backend "local" {}

  required_version = ">= 0.14"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
    shell = {
      source  = "scottwinkler/shell"
      version = "1.7.10"
    }
  }
}

provider "google" {
  region  = var.gcp_region
  project = var.gcp_project
}

# Get current user info for SSH key configuration
data "google_client_openid_userinfo" "me" {}

# =============================================================================
# Required GCP APIs
# =============================================================================

locals {
  required_gcp_services = [
    "deploymentmanager.googleapis.com",
    "compute.googleapis.com",
    "cloudapis.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "networksecurity.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "servicemanagement.googleapis.com",
    "serviceusage.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "orgpolicy.googleapis.com",
    "iap.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each           = toset(local.required_gcp_services)
  project            = var.gcp_project
  service            = each.value
  disable_on_destroy = false
}

# =============================================================================
# OCM Login (non-interactive)
# =============================================================================

resource "shell_script" "ocm_login" {
  lifecycle_commands {
    create = templatefile(
      "${path.module}/templates/ocmlogin.tftpl",
      {
        ocm_token = var.ocm_token
        ocm_url   = var.ocm_url
      }
    )
    delete = "true"
    read   = "true"
  }
}

# =============================================================================
# VPC Module
# =============================================================================

module "vpc" {
  source = "./modules/vpc"

  project      = var.gcp_project
  region       = var.gcp_region
  cluster_name = var.clustername
  routing_mode = var.vpc_routing_mode

  depends_on = [google_project_service.required]

  # Existing VPC configuration
  use_existing_vpc            = var.use_existing_vpc
  existing_vpc_name           = var.existing_vpc_name
  existing_master_subnet_name = var.existing_master_subnet_name
  existing_worker_subnet_name = var.existing_worker_subnet_name
  existing_router_name        = var.existing_router_name

  # CIDR configuration (for new VPC)
  master_cidr_block = var.master_cidr_block
  worker_cidr_block = var.worker_cidr_block

  # NAT configuration
  enable_nat_gateway = var.enable_nat_gateway
}

# =============================================================================
# PSC Module (Private Service Connect)
# =============================================================================

module "psc" {
  source = "./modules/psc"

  project      = var.gcp_project
  region       = var.gcp_region
  cluster_name = var.clustername
  vpc_id       = module.vpc.vpc_id

  # PSC configuration
  enabled               = var.osd_gcp_private && var.osd_gcp_psc
  create_psc_subnet     = !var.use_existing_vpc
  psc_subnet_cidr_block = var.psc_subnet_cidr_block
  psc_endpoint_address  = var.psc_endpoint_address

  # Existing PSC subnet (when using existing VPC)
  existing_psc_subnet_name = var.existing_psc_subnet_name

  depends_on = [module.vpc, google_project_service.required]
}

# =============================================================================
# Bastion Module
# =============================================================================

module "bastion" {
  source = "./modules/bastion"

  project      = var.gcp_project
  region       = var.gcp_region
  zone         = var.gcp_zone
  cluster_name = var.clustername
  osd_vpc_id   = module.vpc.vpc_id

  # Bastion configuration
  enabled      = var.enable_osd_gcp_bastion
  routing_mode = var.vpc_routing_mode
  cidr_block   = var.bastion_cidr_block
  machine_type = var.bastion_machine_type
  ssh_key_path = var.bastion_key_loc
  user_email   = data.google_client_openid_userinfo.me.email

  depends_on = [module.vpc, google_project_service.required]
}

# =============================================================================
# WIF Configuration
# =============================================================================

resource "shell_script" "wif_create" {
  count = var.gcp_authentication_type == "workload_identity_federation" && !var.use_existing_wif ? 1 : 0

  lifecycle_commands {
    create = templatefile(
      "${path.module}/templates/wifcreate.tftpl",
      {
        wif_config_name = "${var.clustername}-wif"
        gcp_project     = var.gcp_project
      }
    )
    delete = templatefile(
      "${path.module}/templates/wifdelete.tftpl",
      {
        wif_config_name = "${var.clustername}-wif"
      }
    )
    read = templatefile(
      "${path.module}/templates/wifread.tftpl",
      {
        wif_config_name = "${var.clustername}-wif"
      }
    )
  }

  depends_on = [google_project_service.required, shell_script.ocm_login]
}

# =============================================================================
# Cluster Installation
# =============================================================================

resource "shell_script" "cluster_install" {
  count = var.only_deploy_infra_no_osd ? 0 : 1

  lifecycle_commands {
    create = templatefile(
      "${path.module}/templates/clusterinstall.tftpl",
      {
        cluster_name            = var.clustername
        vpc_name                = module.vpc.vpc_name
        control_plane_subnet    = module.vpc.master_subnet_name
        compute_subnet          = module.vpc.worker_subnet_name
        gcp_region              = var.gcp_region
        gcp_zone                = var.gcp_zone
        gcp_sa_file_loc         = var.gcp_sa_file_loc
        gcp_authentication_type = var.gcp_authentication_type
        wif_config_name         = local.wif_config_name
        osd_gcp_private         = var.osd_gcp_private
        osd_gcp_psc             = var.osd_gcp_psc
        psc_subnet_name         = module.psc.psc_subnet_name
        gcp_availability_zones  = var.gcp_availability_zones
        compute_nodes_count     = var.compute_nodes_count != null ? tostring(var.compute_nodes_count) : ""
        http_proxy              = var.http_proxy
        https_proxy             = var.https_proxy
        no_proxy                = var.no_proxy
        additional_trust_bundle = var.additional_trust_bundle
        domain_prefix           = var.domain_prefix
        compute_machine_type    = var.compute_machine_type
        cluster_version         = var.cluster_version
        machine_cidr            = var.machine_cidr
      }
    )
    delete = templatefile(
      "${path.module}/templates/clusterdestroy.tftpl",
      {
        cluster_name         = var.clustername
        vpc_name             = module.vpc.vpc_name
        control_plane_subnet = module.vpc.master_subnet_name
        compute_subnet       = module.vpc.worker_subnet_name
        gcp_region           = var.gcp_region
        gcp_sa_file_loc      = var.gcp_sa_file_loc
      }
    )
  }

  depends_on = [
    module.vpc,
    module.psc,
    shell_script.wif_create,
    google_project_service.required,
    shell_script.ocm_login
  ]
}

# =============================================================================
# Additional Machine Pools
# =============================================================================

module "additional_machine_pools" {
  source   = "./modules/machine-pool"
  for_each = var.only_deploy_infra_no_osd ? {} : {
    for pool in var.additional_machine_pools : pool.name => pool
  }

  cluster_name      = var.clustername
  name              = each.value.name
  instance_type     = each.value.instance_type
  replicas          = each.value.replicas
  labels            = each.value.labels
  taints            = each.value.taints
  availability_zone = each.value.availability_zone

  # Autoscaling (if min/max replicas specified)
  autoscaling = each.value.min_replicas != null && each.value.max_replicas != null ? {
    enabled      = true
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas
  } : null

  depends_on = [shell_script.cluster_install]
}

# =============================================================================
# Locals
# =============================================================================

locals {
  wif_config_name = var.use_existing_wif ? var.existing_wif_config_name : "${var.clustername}-wif"
}
