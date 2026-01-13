# =============================================================================
# VPC Module - Variables
# =============================================================================

variable "project" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "cluster_name" {
  type        = string
  description = "Name of the cluster (used as prefix for resources)"
}

variable "routing_mode" {
  type        = string
  description = "VPC routing mode (REGIONAL or GLOBAL)"
  default     = "REGIONAL"
}

# ============================================
# Existing VPC Configuration
# ============================================

variable "use_existing_vpc" {
  type        = bool
  description = "Whether to use an existing VPC or create a new one"
  default     = false
}

variable "existing_vpc_name" {
  type        = string
  description = "Name of the existing VPC (required when use_existing_vpc = true)"
  default     = ""
}

variable "existing_master_subnet_name" {
  type        = string
  description = "Name of the existing master subnet (required when use_existing_vpc = true)"
  default     = ""
}

variable "existing_worker_subnet_name" {
  type        = string
  description = "Name of the existing worker subnet (required when use_existing_vpc = true)"
  default     = ""
}

variable "existing_router_name" {
  type        = string
  description = "Name of the existing Cloud Router (optional)"
  default     = ""
}

# ============================================
# CIDR Configuration (for new VPC)
# ============================================

variable "master_cidr_block" {
  type        = string
  description = "CIDR block for master/control-plane subnet"
  default     = "10.0.0.0/17"
}

variable "worker_cidr_block" {
  type        = string
  description = "CIDR block for worker/compute subnet"
  default     = "10.0.128.0/17"
}

# ============================================
# NAT Gateway Configuration
# ============================================

variable "enable_nat_gateway" {
  type        = bool
  description = "Whether to create NAT gateways for internet connectivity"
  default     = true
}
