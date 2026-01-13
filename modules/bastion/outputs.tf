# =============================================================================
# Bastion Module - Outputs
# =============================================================================

output "bastion_vpc_id" {
  description = "The ID of the bastion VPC"
  value       = var.enabled ? google_compute_network.bastion_vpc[0].id : null
}

output "bastion_vpc_name" {
  description = "The name of the bastion VPC"
  value       = var.enabled ? google_compute_network.bastion_vpc[0].name : null
}

output "bastion_subnet_id" {
  description = "The ID of the bastion subnet"
  value       = var.enabled ? google_compute_subnetwork.bastion_subnet[0].id : null
}

output "bastion_vm_name" {
  description = "The name of the bastion VM"
  value       = var.enabled ? google_compute_instance.bastion[0].name : null
}

output "bastion_external_ip" {
  description = "The external IP address of the bastion VM"
  value       = var.enabled ? google_compute_instance.bastion[0].network_interface[0].access_config[0].nat_ip : null
}

output "bastion_internal_ip" {
  description = "The internal IP address of the bastion VM"
  value       = var.enabled ? google_compute_instance.bastion[0].network_interface[0].network_ip : null
}
