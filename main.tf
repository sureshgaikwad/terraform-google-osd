terraform {
  backend "local" {}

  required_version = ">= 0.14"
  required_providers {
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

resource "shell_script" "cluster_install" {
  count = var.only_deploy_infra_no_osd ? 0 : 1

  lifecycle_commands {
    create = templatefile(
      "${path.module}/templates/clusterinstall.tftpl",
      {
        cluster_name            = var.clustername
        vpc_name                = local.vpc_name
        control_plane_subnet    = local.master_subnet_name
        compute_subnet          = local.worker_subnet_name
        gcp_region              = var.gcp_region
        gcp_zone                = var.gcp_zone 
        gcp_sa_file_loc         = var.gcp_sa_file_loc
        gcp_authentication_type = var.gcp_authentication_type
        wif_config_name         = var.use_existing_wif ? var.existing_wif_config_name : "${var.clustername}-wif"
        osd_gcp_private         = var.osd_gcp_private
        osd_gcp_psc             = var.osd_gcp_psc
        psc_subnet_name         = local.psc_subnet_name
        gcp_availability_zones  = var.gcp_availability_zones
        compute_nodes_count     = var.compute_nodes_count != null ? tostring(var.compute_nodes_count) : ""
        http_proxy              = var.http_proxy
        https_proxy             = var.https_proxy
        no_proxy                = var.no_proxy
        additional_trust_bundle = var.additional_trust_bundle
        domain_prefix           = var.domain_prefix
        compute_machine_type    = var.compute_machine_type
    })
    delete = templatefile(
      "${path.module}/templates/clusterdestroy.tftpl",
      {
        cluster_name         = var.clustername
        vpc_name             = local.vpc_name
        control_plane_subnet = local.master_subnet_name
        compute_subnet       = local.worker_subnet_name
        gcp_region           = var.gcp_region
        gcp_sa_file_loc      = var.gcp_sa_file_loc
    })
  }

  depends_on = [
    google_compute_router.router,
    google_compute_router_nat.nat-master,
    google_compute_router_nat.nat-worker,
    shell_script.wif_create,
    google_compute_global_forwarding_rule.psc_google_apis,  
    google_dns_record_set.psc_googleapis_a           
  ]
}

# WIF configuration - only created when:
# - gcp_authentication_type = "workload_identity_federation"
# - use_existing_wif = false
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
}

# Local to determine which WIF config name to use
locals {
  wif_config_name = var.use_existing_wif ? var.existing_wif_config_name : "${var.clustername}-wif"
}
