# =============================================================================
# OSD GCP Machine Pool Module - Outputs
# =============================================================================

output "name" {
  description = "Name of the machine pool"
  value       = var.name
}

output "instance_type" {
  description = "Instance type of the machine pool"
  value       = var.instance_type
}

output "replicas" {
  description = "Number of replicas"
  value       = var.replicas
}
