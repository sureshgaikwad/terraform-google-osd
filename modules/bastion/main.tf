# =============================================================================
# Bastion Module - Main
# =============================================================================
# Creates bastion infrastructure for private cluster access
# Includes: VPC, subnet, VPC peering, and bastion VM
# =============================================================================

# ============================================
# Bastion VPC and Subnet
# ============================================

resource "google_compute_network" "bastion_vpc" {
  count                   = var.enabled ? 1 : 0
  project                 = var.project
  name                    = "${var.cluster_name}-bastion-vpc"
  auto_create_subnetworks = false
  routing_mode            = var.routing_mode
}

resource "google_compute_subnetwork" "bastion_subnet" {
  count         = var.enabled ? 1 : 0
  project       = var.project
  name          = "${var.cluster_name}-bastion-subnet"
  ip_cidr_range = var.cidr_block
  region        = var.region
  network       = var.osd_vpc_id
}

# ============================================
# VPC Peering
# ============================================

resource "google_compute_network_peering" "osd_to_bastion" {
  count                               = var.enabled ? 1 : 0
  name                                = "${var.cluster_name}-peering-osd-to-bastion"
  network                             = var.osd_vpc_id
  peer_network                        = google_compute_network.bastion_vpc[0].self_link
  export_custom_routes                = true
  import_custom_routes                = true
  export_subnet_routes_with_public_ip = true
  import_subnet_routes_with_public_ip = true
}

resource "google_compute_network_peering" "bastion_to_osd" {
  count                               = var.enabled ? 1 : 0
  name                                = "${var.cluster_name}-peering-bastion-to-osd"
  network                             = google_compute_network.bastion_vpc[0].self_link
  peer_network                        = var.osd_vpc_id
  export_custom_routes                = true
  import_custom_routes                = true
  export_subnet_routes_with_public_ip = true
  import_subnet_routes_with_public_ip = true
}

# ============================================
# Bastion VM Instance
# ============================================

resource "google_compute_instance" "bastion" {
  count        = var.enabled ? 1 : 0
  name         = "${var.cluster_name}-bastion-vm"
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  metadata = {
    ssh-keys       = "${split("@", var.user_email)[0]}:${file(var.ssh_key_path)}"
    startup-script = <<-EOF
    #!/bin/bash
    # Install utilities
    sudo apt-get update
    sudo apt-get install -y telnet wget bash-completion jq
    
    # Install OpenShift CLI
    wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
    tar -xvf openshift-client-linux.tar.gz
    sudo mv oc kubectl /usr/bin/
    oc completion bash > oc_bash_completion
    sudo cp oc_bash_completion /etc/bash_completion.d/
    
    # Log completion
    now=$(date)
    echo "Finished at $now" >> /tmp/post-install-osd.txt
    EOF
  }

  network_interface {
    subnetwork = google_compute_subnetwork.bastion_subnet[0].id
    access_config {
      # Ephemeral public IP
    }
  }

  tags = ["${var.cluster_name}-bastion-vm"]
}
