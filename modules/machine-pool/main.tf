# =============================================================================
# OSD GCP Machine Pool Module
# =============================================================================
# Creates additional machine pools for OpenShift Dedicated clusters on GCP.
#
# For multi-AZ clusters:
# - Replicas must be multiple of zone count, OR
# - Specify availability_zone for single-zone machine pool
# =============================================================================

terraform {
  required_providers {
    shell = {
      source  = "scottwinkler/shell"
      version = ">= 1.7.10"
    }
  }
}

locals {
  # Build labels string: key=value,key2=value2
  labels_str = join(",", [for k, v in var.labels : "${k}=${v}"])
  
  # Build taints string: key=value:effect,key2=value2:effect2
  taints_str = join(",", [for t in var.taints : "${t.key}=${t.value}:${t.effect}"])
  
  # Availability zone (empty string if null)
  az = var.availability_zone != null ? var.availability_zone : ""
  
  # Autoscaling flags
  use_autoscaling = var.autoscaling != null ? var.autoscaling.enabled : false
  min_replicas    = var.autoscaling != null ? var.autoscaling.min_replicas : 0
  max_replicas    = var.autoscaling != null ? var.autoscaling.max_replicas : 0
}

resource "shell_script" "machine_pool" {
  lifecycle_commands {
    create = <<-EOT
      #!/bin/bash
      set -e
      
      # Get cluster ID from name
      CLUSTER_ID=$(ocm get /api/clusters_mgmt/v1/clusters \
        --parameter search="name = '${var.cluster_name}'" 2>/dev/null \
        | jq -r '.items[] | select(.state == "ready") | .id' | head -1)
      
      [ -z "$CLUSTER_ID" ] && { echo "Cluster '${var.cluster_name}' not found or not ready"; exit 1; }
      
      # Build command
      CMD="ocm create machinepool --cluster=$CLUSTER_ID"
      CMD="$CMD --instance-type=${var.instance_type}"
      
      # Scaling
      %{if local.use_autoscaling}
      CMD="$CMD --enable-autoscaling --min-replicas=${local.min_replicas} --max-replicas=${local.max_replicas}"
      %{else}
      CMD="$CMD --replicas=${var.replicas}"
      %{endif}
      
      # Labels
      [ -n "${local.labels_str}" ] && CMD="$CMD --labels='${local.labels_str}'"
      
      # Taints
      [ -n "${local.taints_str}" ] && CMD="$CMD --taints='${local.taints_str}'"
      
      # Availability zone (for single-AZ pool in multi-AZ cluster)
      [ -n "${local.az}" ] && CMD="$CMD --availability-zone=${local.az}"
      
      # Pool name
      CMD="$CMD ${var.name}"
      
      echo "Creating machine pool '${var.name}'..."
      eval $CMD
      echo "Machine pool '${var.name}' created successfully"
    EOT

    read = <<-EOT
      #!/bin/bash
      CLUSTER_ID=$(ocm get /api/clusters_mgmt/v1/clusters \
        --parameter search="name = '${var.cluster_name}'" 2>/dev/null \
        | jq -r '.items[] | select(.state == "ready") | .id' | head -1)
      
      [ -z "$CLUSTER_ID" ] && { echo "{}"; exit 0; }
      
      ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID/machine_pools/${var.name} 2>/dev/null \
        | jq -c '{id: .id, replicas: .replicas, instance_type: .instance_type}' || echo "{}"
    EOT

    update = <<-EOT
      #!/bin/bash
      set -e
      
      CLUSTER_ID=$(ocm get /api/clusters_mgmt/v1/clusters \
        --parameter search="name = '${var.cluster_name}'" 2>/dev/null \
        | jq -r '.items[] | select(.state == "ready") | .id' | head -1)
      
      [ -z "$CLUSTER_ID" ] && { echo "Cluster not found"; exit 1; }
      
      CMD="ocm edit machinepool --cluster=$CLUSTER_ID"
      
      %{if local.use_autoscaling}
      CMD="$CMD --enable-autoscaling --min-replicas=${local.min_replicas} --max-replicas=${local.max_replicas}"
      %{else}
      CMD="$CMD --replicas=${var.replicas}"
      %{endif}
      
      [ -n "${local.labels_str}" ] && CMD="$CMD --labels='${local.labels_str}'"
      [ -n "${local.taints_str}" ] && CMD="$CMD --taints='${local.taints_str}'"
      
      CMD="$CMD ${var.name}"
      
      echo "Updating machine pool '${var.name}'..."
      eval $CMD
    EOT

    delete = <<-EOT
      #!/bin/bash
      CLUSTER_ID=$(ocm get /api/clusters_mgmt/v1/clusters \
        --parameter search="name = '${var.cluster_name}'" 2>/dev/null \
        | jq -r '.items[0].id // empty')
      
      [ -z "$CLUSTER_ID" ] && { echo "Cluster not found, assuming deleted"; exit 0; }
      
      echo "Deleting machine pool '${var.name}'..."
      ocm delete machinepool --cluster=$CLUSTER_ID ${var.name} 2>/dev/null || true
      echo "Machine pool '${var.name}' deleted"
    EOT
  }

  triggers = {
    replicas      = var.replicas
    instance_type = var.instance_type
    labels        = local.labels_str
    taints        = local.taints_str
    az            = local.az
  }
}
