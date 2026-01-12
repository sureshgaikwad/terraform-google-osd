# =============================================================================
# OSD GCP Machine Pool Module - Variables
# =============================================================================

variable "cluster_id" {
  type        = string
  description = "The OCM cluster ID or name where the machine pool will be created."
}

variable "machine_pool_name" {
  type        = string
  description = <<EOF
Name/ID of the machine pool. Must be unique within the cluster.
Example: "worker-pool-1", "gpu-nodes", "memory-optimized"
EOF

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.machine_pool_name)) && length(var.machine_pool_name) <= 15
    error_message = "Machine pool name must be 2-15 characters, start with letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "instance_type" {
  type        = string
  description = <<EOF
GCP instance type for the machine pool nodes.
Examples:
  - custom-4-32768-ext   (4 vCPU, 32GB RAM) - Default for OSD
  - n2-standard-4        (4 vCPU, 16GB RAM)
  - n2-standard-8        (8 vCPU, 32GB RAM)
  - n2-highmem-4         (4 vCPU, 32GB RAM)
  - n2-highmem-8         (8 vCPU, 64GB RAM)
  - e2-standard-4        (4 vCPU, 16GB RAM)
  - c2-standard-4        (4 vCPU, 16GB RAM) - Compute-optimized
  - a2-highgpu-1g        (12 vCPU, 85GB RAM, 1 GPU) - GPU nodes
EOF
}

# =============================================================================
# Scaling Configuration
# =============================================================================

variable "enable_autoscaling" {
  type        = bool
  description = "Enable autoscaling for this machine pool."
  default     = false
}

variable "replicas" {
  type        = number
  description = <<EOF
Number of nodes in the machine pool (when autoscaling is disabled).
For multi-AZ clusters, this should ideally be a multiple of availability zones.
EOF
  default     = null

  validation {
    condition     = try(var.replicas == null, false) || try(var.replicas >= 0, true)
    error_message = "Replicas must be a non-negative number."
  }
}

variable "min_replicas" {
  type        = number
  description = "Minimum number of nodes when autoscaling is enabled."
  default     = null

  validation {
    condition     = try(var.min_replicas == null, false) || try(var.min_replicas >= 0, true)
    error_message = "Minimum replicas must be a non-negative number."
  }
}

variable "max_replicas" {
  type        = number
  description = "Maximum number of nodes when autoscaling is enabled."
  default     = null

  validation {
    condition     = try(var.max_replicas == null, false) || try(var.max_replicas >= 1, true)
    error_message = "Maximum replicas must be at least 1."
  }
}

# =============================================================================
# Node Configuration
# =============================================================================

variable "labels" {
  type        = map(string)
  description = <<EOF
Kubernetes labels to apply to nodes in this machine pool.
Example: { "workload-type" = "gpu", "team" = "ml" }
Note: These labels will overwrite any manual modifications to node labels.
EOF
  default     = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  description = <<EOF
Kubernetes taints to apply to nodes in this machine pool.
Effect must be one of: NoSchedule, PreferNoSchedule, NoExecute
Example:
  [
    {
      key    = "dedicated"
      value  = "gpu"
      effect = "NoSchedule"
    }
  ]
Note: These taints will overwrite any manual modifications to node taints.
EOF
  default     = []

  validation {
    condition = alltrue([
      for t in var.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)
    ])
    error_message = "Taint effect must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
}

# =============================================================================
# Multi-AZ Configuration
# =============================================================================

variable "availability_zone" {
  type        = string
  description = <<EOF
Specific availability zone for this machine pool (optional).
Use this to create a single-AZ machine pool within a multi-AZ cluster.
Example: "us-central1-a"
If not set, nodes will be distributed across all cluster availability zones.
EOF
  default     = ""
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "secure_boot_enabled" {
  type        = bool
  description = <<EOF
Enable Secure Boot for Shielded VMs in this machine pool.
This overrides the cluster-level secure boot configuration.
EOF
  default     = false
}
