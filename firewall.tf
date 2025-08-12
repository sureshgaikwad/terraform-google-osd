# firewall rules for PSC
resource "google_compute_firewall" "psc_allow_https" {
  count    = var.osd_gcp_psc ? 1 : 0
  name     = "${var.clustername}-psc-allow-https"
  network  = google_compute_network.vpc_network.id
  project  = var.gcp_project
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block
  ]
  
  destination_ranges = [var.psc_subnet_cidr_block]
  
  direction = "INGRESS"
}

resource "google_compute_firewall" "psc_allow_dns" {
  count    = var.osd_gcp_psc ? 1 : 0
  name     = "${var.clustername}-psc-allow-dns"
  network  = google_compute_network.vpc_network.id
  project  = var.gcp_project
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }

  source_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block
  ]
  
  direction = "INGRESS"
}