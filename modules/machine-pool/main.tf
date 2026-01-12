# =============================================================================
# OSD GCP Machine Pool Module
# =============================================================================
# This module creates and manages machine pools for OpenShift Dedicated clusters
# on Google Cloud Platform using the OCM CLI.
#
# Similar to the ROSA HCP machine pool module, this allows you to:
# - Create additional worker node pools with different instance types
# - Configure autoscaling for machine pools
# - Apply labels and taints for workload scheduling
# - Create single-AZ machine pools in multi-AZ clusters
# =============================================================================

terraform {
  required_providers {
    shell = {
      source  = "scottwinkler/shell"
      version = ">= 1.7.10"
    }
  }
}

# Build labels string from map
locals {
  labels_string = length(var.labels) > 0 ? join(",", [
    for k, v in var.labels : "${k}=${v}"
  ]) : ""

  taints_string = length(var.taints) > 0 ? join(",", [
    for t in var.taints : "${t.key}=${t.value}:${t.effect}"
  ]) : ""

  # Build scaling flags
  scaling_flags = var.enable_autoscaling ? (
    "--enable-autoscaling --min-replicas=${var.min_replicas} --max-replicas=${var.max_replicas}"
  ) : (
    "--replicas=${var.replicas}"
  )
}

resource "shell_script" "machine_pool" {
  lifecycle_commands {
    create = <<-EOT
      #!/bin/bash
      set -e

      echo "Creating machine pool '${var.machine_pool_name}' for cluster '${var.cluster_id}'..."

      # Build the ocm create machinepool command
      CMD="ocm create machinepool"
      CMD="$CMD --cluster=${var.cluster_id}"
      CMD="$CMD --instance-type=${var.instance_type}"

      # Scaling configuration
      %{if var.enable_autoscaling}
      CMD="$CMD --enable-autoscaling"
      CMD="$CMD --min-replicas=${var.min_replicas}"
      CMD="$CMD --max-replicas=${var.max_replicas}"
      %{else}
      CMD="$CMD --replicas=${var.replicas}"
      %{endif}

      # Labels
      %{if length(var.labels) > 0}
      CMD="$CMD --labels='${local.labels_string}'"
      %{endif}

      # Taints
      %{if length(var.taints) > 0}
      CMD="$CMD --taints='${local.taints_string}'"
      %{endif}

      # Availability zone (for single-AZ machine pool in multi-AZ cluster)
      %{if var.availability_zone != null && var.availability_zone != ""}
      CMD="$CMD --availability-zone=${var.availability_zone}"
      %{endif}

      # Secure boot for shielded VMs
      %{if var.secure_boot_enabled}
      CMD="$CMD --secure-boot-for-shielded-vms"
      %{endif}

      # Machine pool name/ID (last argument)
      CMD="$CMD ${var.machine_pool_name}"

      echo "Executing: $CMD"
      eval $CMD

      # Wait for machine pool to be created
      echo "Waiting for machine pool to be provisioned..."
      sleep 10

      # Get machine pool details
      POOL_INFO=$(ocm get /api/clusters_mgmt/v1/clusters/${var.cluster_id}/machine_pools/${var.machine_pool_name} 2>/dev/null || echo "{}")
      
      if echo "$POOL_INFO" | jq -e '.id' > /dev/null 2>&1; then
        echo "Machine pool created successfully!"
        echo "$POOL_INFO" | jq '{
          id: .id,
          instance_type: .instance_type,
          replicas: .replicas,
          autoscaling: .autoscaling,
          availability_zone: .availability_zone,
          labels: .labels,
          taints: .taints
        }'
      else
        echo "Machine pool creation initiated. It may take a few minutes for nodes to be ready."
      fi
    EOT

    read = <<-EOT
      #!/bin/bash
      
      POOL_INFO=$(ocm get /api/clusters_mgmt/v1/clusters/${var.cluster_id}/machine_pools/${var.machine_pool_name} 2>/dev/null || echo "{}")
      
      if echo "$POOL_INFO" | jq -e '.id' > /dev/null 2>&1; then
        echo "$POOL_INFO" | jq -c '{
          id: .id,
          instance_type: .instance_type,
          replicas: .replicas,
          autoscaling: .autoscaling,
          availability_zone: .availability_zone
        }'
      else
        echo "{}"
      fi
    EOT

    update = <<-EOT
      #!/bin/bash
      set -e

      echo "Updating machine pool '${var.machine_pool_name}' for cluster '${var.cluster_id}'..."

      # Build the ocm edit machinepool command
      CMD="ocm edit machinepool"
      CMD="$CMD --cluster=${var.cluster_id}"

      # Scaling configuration
      %{if var.enable_autoscaling}
      CMD="$CMD --enable-autoscaling"
      CMD="$CMD --min-replicas=${var.min_replicas}"
      CMD="$CMD --max-replicas=${var.max_replicas}"
      %{else}
      CMD="$CMD --replicas=${var.replicas}"
      %{endif}

      # Labels
      %{if length(var.labels) > 0}
      CMD="$CMD --labels='${local.labels_string}'"
      %{endif}

      # Taints
      %{if length(var.taints) > 0}
      CMD="$CMD --taints='${local.taints_string}'"
      %{endif}

      # Machine pool name/ID
      CMD="$CMD ${var.machine_pool_name}"

      echo "Executing: $CMD"
      eval $CMD

      echo "Machine pool updated successfully!"
    EOT

    delete = <<-EOT
      #!/bin/bash
      set -e

      echo "Deleting machine pool '${var.machine_pool_name}' from cluster '${var.cluster_id}'..."

      # Check if machine pool exists
      POOL_EXISTS=$(ocm get /api/clusters_mgmt/v1/clusters/${var.cluster_id}/machine_pools/${var.machine_pool_name} 2>/dev/null | jq -r '.id // empty')

      if [ -z "$POOL_EXISTS" ]; then
        echo "Machine pool does not exist, nothing to delete."
        exit 0
      fi

      # Delete the machine pool
      ocm delete machinepool --cluster=${var.cluster_id} ${var.machine_pool_name}

      echo "Machine pool deletion initiated..."

      # Wait for machine pool to be deleted (max 10 minutes)
      MAX_WAIT=600
      WAIT_TIME=0
      CHECK_INTERVAL=15

      while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        POOL_EXISTS=$(ocm get /api/clusters_mgmt/v1/clusters/${var.cluster_id}/machine_pools/${var.machine_pool_name} 2>/dev/null | jq -r '.id // empty')
        
        if [ -z "$POOL_EXISTS" ]; then
          echo "Machine pool deleted successfully!"
          exit 0
        fi
        
        echo "Waiting for machine pool deletion... ($WAIT_TIME seconds)"
        sleep $CHECK_INTERVAL
        WAIT_TIME=$((WAIT_TIME + CHECK_INTERVAL))
      done

      echo "Warning: Machine pool deletion is taking longer than expected. It will be cleaned up in the background."
    EOT
  }

  # Trigger updates when these values change
  triggers = {
    instance_type       = var.instance_type
    enable_autoscaling  = var.enable_autoscaling
    replicas            = var.replicas != null ? var.replicas : ""
    min_replicas        = var.min_replicas != null ? var.min_replicas : ""
    max_replicas        = var.max_replicas != null ? var.max_replicas : ""
    labels              = local.labels_string
    taints              = local.taints_string
    availability_zone   = var.availability_zone != null ? var.availability_zone : ""
    secure_boot_enabled = var.secure_boot_enabled
  }
}
