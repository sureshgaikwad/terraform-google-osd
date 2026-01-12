# =============================================================================
# Additional Machine Pools for OSD Cluster
# =============================================================================
# These machine pools are created AFTER the cluster is ready.
# The default "worker" pool is created during cluster installation.
# Configure pools via the additional_machine_pools variable in terraform.tfvars
# =============================================================================

module "additional_machine_pools" {
  source   = "./modules/machine-pool"
  for_each = var.only_deploy_infra_no_osd ? {} : {
    for pool in var.additional_machine_pools : pool.name => pool
  }

  cluster_id        = var.clustername
  machine_pool_name = each.value.name
  instance_type     = each.value.instance_type

  # Fixed replicas or autoscaling
  replicas     = each.value.replicas
  min_replicas = each.value.min_replicas
  max_replicas = each.value.max_replicas

  # Node configuration
  labels            = each.value.labels
  taints            = each.value.taints
  availability_zone = each.value.availability_zone

  # Ensure cluster is ready before creating machine pool
  depends_on = [shell_script.cluster_install]
}

# =============================================================================
# Outputs
# =============================================================================

output "additional_machine_pools" {
  description = "Additional machine pools created for the cluster"
  value = var.only_deploy_infra_no_osd ? {} : {
    for name, pool in module.additional_machine_pools : name => {
      name          = pool.machine_pool_id
      instance_type = pool.instance_type
      replicas      = pool.replicas
    }
  }
}
