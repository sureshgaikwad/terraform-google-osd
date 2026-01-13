# =============================================================================
# Bastion Module - Variables
# =============================================================================

variable "project" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "zone" {
  type        = string
  description = "GCP zone for bastion VM"
}

variable "cluster_name" {
  type        = string
  description = "Name of the cluster (used as prefix for resources)"
}

variable "osd_vpc_id" {
  type        = string
  description = "The ID of the OSD VPC to peer with"
}

# ============================================
# Bastion Configuration
# ============================================

variable "enabled" {
  type        = bool
  description = "Whether to create bastion resources"
  default     = false
}

variable "routing_mode" {
  type        = string
  description = "VPC routing mode (REGIONAL or GLOBAL)"
  default     = "REGIONAL"
}

variable "cidr_block" {
  type        = string
  description = "CIDR block for bastion subnet"
  default     = "10.10.0.0/24"
}

variable "machine_type" {
  type        = string
  description = "Machine type for bastion VM"
  default     = "e2-small"
}

variable "ssh_key_path" {
  type        = string
  description = "Path to SSH public key for bastion access"
  default     = "~/.ssh/id_rsa.pub"
}

variable "user_email" {
  type        = string
  description = "Email of the user for SSH key configuration"
}
