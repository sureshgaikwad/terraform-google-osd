# =============================================================================
# OSD GCP Machine Pool Module - Variables
# =============================================================================

variable "cluster_name" {
  type        = string
  description = "Name of the OSD cluster"
}

variable "name" {
  type        = string
  description = "Name of the machine pool (must be unique within cluster)"
}

variable "instance_type" {
  type        = string
  description = "GCP instance type (e.g., n2-standard-4, n2-standard-8)"
}

variable "replicas" {
  type        = number
  description = <<EOF
Number of nodes. For multi-AZ clusters:
- Must be multiple of zone count (e.g., 3, 6, 9 for 3-zone cluster), OR
- Specify availability_zone to create single-zone pool
EOF
  default     = 1
}

variable "autoscaling" {
  type = object({
    enabled      = bool
    min_replicas = number
    max_replicas = number
  })
  description = "Autoscaling configuration. If enabled, replicas is ignored."
  default     = null
}

variable "labels" {
  type        = map(string)
  description = "Node labels (e.g., {workload-type = \"gpu\"})"
  default     = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string  # NoSchedule, PreferNoSchedule, NoExecute
  }))
  description = "Node taints for workload isolation"
  default     = []
}

variable "availability_zone" {
  type        = string
  description = "Specific AZ for single-zone pool in multi-AZ cluster (e.g., us-central1-a)"
  default     = null
}
