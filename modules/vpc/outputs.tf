# =============================================================================
# VPC Module - Outputs
# =============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = local.vpc_id
}

output "vpc_name" {
  description = "The name of the VPC"
  value       = local.vpc_name
}

output "master_subnet_id" {
  description = "The ID of the master/control-plane subnet"
  value       = local.master_subnet_id
}

output "master_subnet_name" {
  description = "The name of the master/control-plane subnet"
  value       = local.master_subnet_name
}

output "worker_subnet_id" {
  description = "The ID of the worker/compute subnet"
  value       = local.worker_subnet_id
}

output "worker_subnet_name" {
  description = "The name of the worker/compute subnet"
  value       = local.worker_subnet_name
}

output "router_name" {
  description = "The name of the Cloud Router"
  value       = local.router_name
}

output "nat_master" {
  description = "The NAT gateway for master subnet"
  value       = var.enable_nat_gateway ? google_compute_router_nat.nat_master[0] : null
}

output "nat_worker" {
  description = "The NAT gateway for worker subnet"
  value       = var.enable_nat_gateway ? google_compute_router_nat.nat_worker[0] : null
}
