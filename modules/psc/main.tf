# =============================================================================
# PSC Module - Main
# =============================================================================
# Creates Private Service Connect resources for Google APIs access
# Includes: PSC subnet, global address, forwarding rule, and DNS zones
# =============================================================================

# ============================================
# Data Source for Existing PSC Subnet
# ============================================

data "google_compute_subnetwork" "existing_psc_subnet" {
  count   = var.enabled && !var.create_psc_subnet && var.existing_psc_subnet_name != "" ? 1 : 0
  name    = var.existing_psc_subnet_name
  region  = var.region
  project = var.project
}

# ============================================
# PSC Subnet
# ============================================

resource "google_compute_subnetwork" "psc_subnet" {
  count         = var.enabled && var.create_psc_subnet ? 1 : 0
  name          = "${var.cluster_name}-psc-subnet"
  ip_cidr_range = var.psc_subnet_cidr_block
  region        = var.region
  network       = var.vpc_id
  purpose       = "PRIVATE_SERVICE_CONNECT"
  project       = var.project
}

# ============================================
# PSC Global Address and Forwarding Rule
# ============================================

resource "google_compute_global_address" "psc_google_apis" {
  count        = var.enabled ? 1 : 0
  name         = "pscgapisip"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  address_type = "INTERNAL"
  address      = var.psc_endpoint_address
  network      = var.vpc_id
  project      = var.project
}

resource "google_compute_global_forwarding_rule" "psc_google_apis" {
  count                 = var.enabled ? 1 : 0
  name                  = "pscgapis"
  target                = "all-apis"
  network               = var.vpc_id
  ip_address            = google_compute_global_address.psc_google_apis[0].id
  load_balancing_scheme = ""
  project               = var.project
}

# ============================================
# Private DNS Zones for Google APIs
# ============================================

resource "google_dns_managed_zone" "googleapis" {
  count       = var.enabled ? 1 : 0
  name        = "${var.cluster_name}-googleapis"
  dns_name    = "googleapis.com."
  description = "Private DNS zone for Google APIs"
  project     = var.project
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = var.vpc_id
    }
  }
}

resource "google_dns_record_set" "googleapis_a" {
  count        = var.enabled ? 1 : 0
  name         = "*.${google_dns_managed_zone.googleapis[0].dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.googleapis[0].name
  rrdatas      = [google_compute_global_address.psc_google_apis[0].address]
  project      = var.project
}

# ============================================
# Private DNS Zone for GCR
# ============================================

resource "google_dns_managed_zone" "gcr" {
  count       = var.enabled ? 1 : 0
  name        = "${var.cluster_name}-gcr"
  dns_name    = "gcr.io."
  description = "Private DNS zone for GCR"
  project     = var.project
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = var.vpc_id
    }
  }
}

resource "google_dns_record_set" "gcr_a" {
  count        = var.enabled ? 1 : 0
  name         = "*.${google_dns_managed_zone.gcr[0].dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.gcr[0].name
  rrdatas      = [google_compute_global_address.psc_google_apis[0].address]
  project      = var.project
}

# ============================================
# Local Values
# ============================================

locals {
  psc_subnet_name = var.enabled ? (
    var.create_psc_subnet ? google_compute_subnetwork.psc_subnet[0].name : data.google_compute_subnetwork.existing_psc_subnet[0].name
  ) : ""
}
