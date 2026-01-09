
# ============================================
# VPC Configuration
# Supports both creating new VPC or using existing VPC
# ============================================

# Data sources for existing VPC (only used when use_existing_vpc = true)
data "google_compute_network" "existing_vpc" {
  count   = var.use_existing_vpc ? 1 : 0
  name    = var.existing_vpc_name
  project = var.gcp_project
}

data "google_compute_subnetwork" "existing_master_subnet" {
  count   = var.use_existing_vpc ? 1 : 0
  name    = var.existing_master_subnet_name
  region  = var.gcp_region
  project = var.gcp_project
}

data "google_compute_subnetwork" "existing_worker_subnet" {
  count   = var.use_existing_vpc ? 1 : 0
  name    = var.existing_worker_subnet_name
  region  = var.gcp_region
  project = var.gcp_project
}

data "google_compute_subnetwork" "existing_psc_subnet" {
  count   = var.use_existing_vpc && var.osd_gcp_psc && var.existing_psc_subnet_name != "" ? 1 : 0
  name    = var.existing_psc_subnet_name
  region  = var.gcp_region
  project = var.gcp_project
}

data "google_compute_router" "existing_router" {
  count   = var.use_existing_vpc && var.existing_router_name != "" ? 1 : 0
  name    = var.existing_router_name
  network = data.google_compute_network.existing_vpc[0].name
  region  = var.gcp_region
  project = var.gcp_project
}

# Resource for new VPC (only created when use_existing_vpc = false)
resource "google_compute_network" "vpc_network" {
  count                   = var.use_existing_vpc ? 0 : 1
  project                 = var.gcp_project
  name                    = "${var.clustername}-vpc"
  auto_create_subnetworks = false
  routing_mode            = var.vpc_routing_mode
}

resource "google_compute_subnetwork" "vpc_subnetwork_masters" {
  count                    = var.use_existing_vpc ? 0 : 1
  project                  = var.gcp_project
  name                     = "${var.clustername}-master-subnet"
  ip_cidr_range            = var.master_cidr_block
  region                   = var.gcp_region
  network                  = google_compute_network.vpc_network[0].id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "vpc_subnetwork_workers" {
  count                    = var.use_existing_vpc ? 0 : 1
  project                  = var.gcp_project
  name                     = "${var.clustername}-worker-subnet"
  ip_cidr_range            = var.worker_cidr_block
  region                   = var.gcp_region
  network                  = google_compute_network.vpc_network[0].id
  private_ip_google_access = true
}

# Cloud Router - created if:
# - Creating new VPC (use_existing_vpc = false), OR
# - Using existing VPC but no existing router specified
resource "google_compute_router" "router" {
  count   = var.use_existing_vpc && var.existing_router_name != "" ? 0 : 1
  project = var.gcp_project
  name    = "${var.clustername}-router"
  region  = var.gcp_region
  network = local.vpc_id
}

# NAT Gateways - only created when enable_nat_gateway = true
# When false, internet connectivity must be provided via landing zone or other means
resource "google_compute_router_nat" "nat-master" {
  count                              = var.enable_nat_gateway ? 1 : 0
  name                               = "${var.clustername}-nat-master"
  router                             = local.router_name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = local.master_subnet_id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  min_ports_per_vm                    = "7168"
  enable_endpoint_independent_mapping = false
}

resource "google_compute_router_nat" "nat-worker" {
  count                              = var.enable_nat_gateway ? 1 : 0
  name                               = "${var.clustername}-nat-worker"
  router                             = local.router_name
  region                             = var.gcp_region
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
# Local values for consistent resource references
# These resolve to either existing or newly created resources
# ============================================

locals {
  # VPC references
  vpc_id   = var.use_existing_vpc ? data.google_compute_network.existing_vpc[0].id : google_compute_network.vpc_network[0].id
  vpc_name = var.use_existing_vpc ? data.google_compute_network.existing_vpc[0].name : google_compute_network.vpc_network[0].name
  
  # Master subnet references
  master_subnet_id   = var.use_existing_vpc ? data.google_compute_subnetwork.existing_master_subnet[0].id : google_compute_subnetwork.vpc_subnetwork_masters[0].id
  master_subnet_name = var.use_existing_vpc ? data.google_compute_subnetwork.existing_master_subnet[0].name : google_compute_subnetwork.vpc_subnetwork_masters[0].name
  
  # Worker subnet references
  worker_subnet_id   = var.use_existing_vpc ? data.google_compute_subnetwork.existing_worker_subnet[0].id : google_compute_subnetwork.vpc_subnetwork_workers[0].id
  worker_subnet_name = var.use_existing_vpc ? data.google_compute_subnetwork.existing_worker_subnet[0].name : google_compute_subnetwork.vpc_subnetwork_workers[0].name
  
  # PSC subnet reference (only when PSC is enabled)
  psc_subnet_name = var.osd_gcp_psc ? (
    var.use_existing_vpc ? data.google_compute_subnetwork.existing_psc_subnet[0].name : google_compute_subnetwork.psc_subnet[0].name
  ) : ""
  
  # Router reference
  router_name = var.use_existing_vpc && var.existing_router_name != "" ? data.google_compute_router.existing_router[0].name : google_compute_router.router[0].name
}
