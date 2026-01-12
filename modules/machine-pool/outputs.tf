# =============================================================================
# OSD GCP Machine Pool Module - Outputs
# =============================================================================

output "machine_pool_id" {
  description = "The ID/name of the machine pool"
  value       = var.machine_pool_name
}

output "cluster_id" {
  description = "The cluster ID where the machine pool was created"
  value       = var.cluster_id
}

output "instance_type" {
  description = "The GCP instance type used for nodes in this pool"
  value       = var.instance_type
}

output "replicas" {
  description = "Number of replicas (when autoscaling is disabled)"
  value       = var.enable_autoscaling ? null : var.replicas
}

output "autoscaling" {
  description = "Autoscaling configuration"
  value = var.enable_autoscaling ? {
    enabled      = true
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
  } : null
}

output "labels" {
  description = "Labels applied to nodes in this pool"
  value       = var.labels
}

output "taints" {
  description = "Taints applied to nodes in this pool"
  value       = var.taints
}

output "availability_zone" {
  description = "The availability zone for this machine pool (if single-AZ)"
  value       = var.availability_zone != null && var.availability_zone != "" ? var.availability_zone : null
}
