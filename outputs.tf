# =============================================================================
# OSD on GCP - Outputs
# =============================================================================

# ============================================
# VPC Outputs
# ============================================

output "vpc_name" {
  description = "The name of the VPC"
  value       = module.vpc.vpc_name
}

output "control_plane_subnet" {
  description = "The name of the control plane subnet"
  value       = module.vpc.master_subnet_name
}

output "compute_subnet" {
  description = "The name of the compute/worker subnet"
  value       = module.vpc.worker_subnet_name
}

output "gcp_region" {
  description = "The GCP region"
  value       = var.gcp_region
}

output "use_existing_vpc" {
  description = "Whether existing VPC was used"
  value       = var.use_existing_vpc
}

# ============================================
# PSC Outputs
# ============================================

output "psc_subnet" {
  description = "The name of the PSC subnet"
  value       = var.osd_gcp_psc ? module.psc.psc_subnet_name : null
}

output "psc_endpoint_ip" {
  description = "The IP address of the PSC Google APIs endpoint"
  value       = var.osd_gcp_psc ? module.psc.psc_endpoint_ip : null
}

# ============================================
# Bastion Outputs
# ============================================

output "bastion_vm_name" {
  description = "The name of the bastion VM"
  value       = module.bastion.bastion_vm_name
}

output "bastion_ip_external" {
  description = "The external IP of the bastion VM"
  value       = module.bastion.bastion_external_ip
}

output "bastion_ip_internal" {
  description = "The internal IP of the bastion VM"
  value       = module.bastion.bastion_internal_ip
}

# ============================================
# Machine Pool Outputs
# ============================================

output "additional_machine_pools" {
  description = "Additional machine pools created for the cluster"
  value = var.only_deploy_infra_no_osd ? {} : {
    for name, pool in module.additional_machine_pools : name => {
      name          = pool.name
      instance_type = pool.instance_type
      replicas      = pool.replicas
    }
  }
}
