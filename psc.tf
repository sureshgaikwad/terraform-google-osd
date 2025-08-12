resource "google_compute_subnetwork" "psc_subnet" {
  count         = var.osd_gcp_psc ? 1 : 0
  project       = var.gcp_project
  name          = "${var.clustername}-psc-subnet"
  ip_cidr_range = var.psc_subnet_cidr_block
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

resource "google_compute_address" "psc_endpoint_addresses" {
  for_each = var.osd_gcp_psc ? toset(var.enable_psc_endpoints) : toset([])
  
  name         = "${var.clustername}-psc-${replace(each.key, ".", "-")}"
  region       = var.gcp_region
  project      = var.gcp_project
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  subnetwork   = google_compute_subnetwork.vpc_subnetwork_workers.id
}

resource "google_compute_forwarding_rule" "psc_google_apis" {
  count                 = var.osd_gcp_psc ? 1 : 0
  name                  = "${var.clustername}-psc-google-apis"
  region                = var.gcp_region
  project               = var.gcp_project
  ip_address            = google_compute_address.psc_google_apis[0].address
  network               = google_compute_network.vpc_network.id
  load_balancing_scheme = ""
  target                = "all-apis"
  # This is required for Google APIs PSC
  allow_psc_global_access = false
}

resource "google_compute_address" "psc_google_apis" {
  count        = var.osd_gcp_psc ? 1 : 0
  name         = "${var.clustername}-psc-google-apis"
  region       = var.gcp_region
  project      = var.gcp_project
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  subnetwork   = google_compute_subnetwork.vpc_subnetwork_workers.id
}

resource "google_dns_managed_zone" "psc_googleapis" {
  count       = var.osd_gcp_psc ? 1 : 0
  name        = "${var.clustername}-googleapis"
  dns_name    = "googleapis.com."
  project     = var.gcp_project
  description = "Private DNS zone for PSC googleapis.com"
  
  visibility = "private"
  
  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_network.id
    }
  }
}

resource "google_dns_record_set" "psc_googleapis_a" {
  count        = var.osd_gcp_psc ? 1 : 0
  name         = "private.googleapis.com."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.psc_googleapis[0].name
  project      = var.gcp_project
  rrdatas      = [google_compute_address.psc_google_apis[0].address]
}

resource "google_dns_record_set" "psc_googleapis_cname" {
  count        = var.osd_gcp_psc ? 1 : 0
  name         = "*.googleapis.com."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.psc_googleapis[0].name
  project      = var.gcp_project
  rrdatas      = ["private.googleapis.com."]
}

resource "google_dns_managed_zone" "psc_gcr" {
  count       = var.osd_gcp_psc ? 1 : 0
  name        = "${var.clustername}-gcr"
  dns_name    = "gcr.io."
  project     = var.gcp_project
  description = "Private DNS zone for PSC gcr.io"
  
  visibility = "private"
  
  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_network.id
    }
  }
}

resource "google_dns_record_set" "psc_gcr_a" {
  count        = var.osd_gcp_psc ? 1 : 0
  name         = "gcr.io."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.psc_gcr[0].name
  project      = var.gcp_project
  rrdatas      = [google_compute_address.psc_google_apis[0].address]
}

resource "google_dns_record_set" "psc_gcr_wildcard" {
  count        = var.osd_gcp_psc ? 1 : 0
  name         = "*.gcr.io."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.psc_gcr[0].name
  project      = var.gcp_project
  rrdatas      = ["gcr.io."]
}