# =============================================================================
# VPC Module - Main
# =============================================================================
# Creates VPC, subnets, Cloud Router, and NAT gateways for OSD cluster
# Supports both creating new VPC or using existing VPC
# =============================================================================

# ============================================
# Data Sources for Existing VPC
# ============================================

data "google_compute_network" "existing_vpc" {
  count   = var.use_existing_vpc ? 1 : 0
  name    = var.existing_vpc_name
  project = var.project
}

data "google_compute_subnetwork" "existing_master_subnet" {
  count   = var.use_existing_vpc ? 1 : 0
  name    = var.existing_master_subnet_name
  region  = var.region
  project = var.project
}

data "google_compute_subnetwork" "existing_worker_subnet" {
  count   = var.use_existing_vpc ? 1 : 0
  name    = var.existing_worker_subnet_name
  region  = var.region
  project = var.project
}

data "google_compute_router" "existing_router" {
  count   = var.use_existing_vpc && var.existing_router_name != "" ? 1 : 0
  name    = var.existing_router_name
  network = data.google_compute_network.existing_vpc[0].name
  region  = var.region
  project = var.project
}

# ============================================
# New VPC Resources
# ============================================

resource "google_compute_network" "vpc" {
  count                   = var.use_existing_vpc ? 0 : 1
  project                 = var.project
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = var.routing_mode
}

resource "google_compute_subnetwork" "master_subnet" {
  count                    = var.use_existing_vpc ? 0 : 1
  project                  = var.project
  name                     = "${var.cluster_name}-master-subnet"
  ip_cidr_range            = var.master_cidr_block
  region                   = var.region
  network                  = google_compute_network.vpc[0].id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "worker_subnet" {
  count                    = var.use_existing_vpc ? 0 : 1
  project                  = var.project
  name                     = "${var.cluster_name}-worker-subnet"
  ip_cidr_range            = var.worker_cidr_block
  region                   = var.region
  network                  = google_compute_network.vpc[0].id
  private_ip_google_access = true
}

# ============================================
# Cloud Router
# ============================================

resource "google_compute_router" "router" {
  count   = var.use_existing_vpc && var.existing_router_name != "" ? 0 : 1
  project = var.project
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = local.vpc_id
}

# ============================================
# NAT Gateways
# ============================================

resource "google_compute_router_nat" "nat_master" {
  count                              = var.enable_nat_gateway ? 1 : 0
  name                               = "${var.cluster_name}-nat-master"
  router                             = local.router_name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  
  subnetwork {
    name                    = local.master_subnet_id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  
  min_ports_per_vm                    = "7168"
  enable_endpoint_independent_mapping = false
}

resource "google_compute_router_nat" "nat_worker" {
  count                              = var.enable_nat_gateway ? 1 : 0
  name                               = "${var.cluster_name}-nat-worker"
  router                             = local.router_name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  
  subnetwork {
    name                    = local.worker_subnet_id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  
  min_ports_per_vm                    = "4096"
  enable_endpoint_independent_mapping = false
}

# ============================================
# Local Values
# ============================================

locals {
  # VPC references
  vpc_id   = var.use_existing_vpc ? data.google_compute_network.existing_vpc[0].id : google_compute_network.vpc[0].id
  vpc_name = var.use_existing_vpc ? data.google_compute_network.existing_vpc[0].name : google_compute_network.vpc[0].name
  
  # Master subnet references
  master_subnet_id   = var.use_existing_vpc ? data.google_compute_subnetwork.existing_master_subnet[0].id : google_compute_subnetwork.master_subnet[0].id
  master_subnet_name = var.use_existing_vpc ? data.google_compute_subnetwork.existing_master_subnet[0].name : google_compute_subnetwork.master_subnet[0].name
  
  # Worker subnet references
  worker_subnet_id   = var.use_existing_vpc ? data.google_compute_subnetwork.existing_worker_subnet[0].id : google_compute_subnetwork.worker_subnet[0].id
  worker_subnet_name = var.use_existing_vpc ? data.google_compute_subnetwork.existing_worker_subnet[0].name : google_compute_subnetwork.worker_subnet[0].name
  
  # Router reference
  router_name = var.use_existing_vpc && var.existing_router_name != "" ? data.google_compute_router.existing_router[0].name : google_compute_router.router[0].name
}
