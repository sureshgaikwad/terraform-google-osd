# =============================================================================
# PSC Module - Variables
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

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC network"
}

# ============================================
# PSC Configuration
# ============================================

variable "enabled" {
  type        = bool
  description = "Whether PSC is enabled"
  default     = false
}

variable "create_psc_subnet" {
  type        = bool
  description = "Whether to create the PSC subnet (false if using existing)"
  default     = true
}

variable "psc_subnet_cidr_block" {
  type        = string
  description = "CIDR block for PSC subnet"
  default     = "10.0.0.248/29"
}

variable "psc_endpoint_address" {
  type        = string
  description = "IP address for the PSC Google APIs endpoint"
  default     = "10.0.255.100"
}

# ============================================
# Existing PSC Subnet (when using existing VPC)
# ============================================

variable "existing_psc_subnet_name" {
  type        = string
  description = "Name of existing PSC subnet (when create_psc_subnet = false)"
  default     = ""
}
