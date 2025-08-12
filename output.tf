# output "bastion_vm_name" {
#   value = google_compute_instance.bastion.0.name
# }

# output "bastion_ip_external" {
#   value = google_compute_instance.bastion.0.network_interface.0.access_config.0.nat_ip
# }

# output "bastion_ip_internal" {
#   value = google_compute_instance.bastion.0.network_interface.0.network_ip
# }

output "vpc_name" {
  value = google_compute_network.vpc_network.name
}

output "control_plane_subnet" {
  value = google_compute_subnetwork.vpc_subnetwork_masters.name
}

output "compute_subnet" {
  value = google_compute_subnetwork.vpc_subnetwork_workers.name
}

output "gcp_region" {
  value = var.gcp_region
}

output "psc_subnet" {
  value = var.osd_gcp_psc ? google_compute_subnetwork.psc_subnet[0].name : null
}

output "psc_endpoints" {
  value = var.osd_gcp_psc ? {
    for k, v in google_compute_address.psc_endpoint_addresses : 
    k => v.address
  } : {}
}