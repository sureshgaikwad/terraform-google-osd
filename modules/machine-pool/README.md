# OSD GCP Machine Pool Module

This Terraform module creates and manages additional machine pools for OpenShift Dedicated (OSD) clusters on Google Cloud Platform.

## Features

- ✅ Create additional worker node pools with custom instance types
- ✅ Configure autoscaling with min/max replicas
- ✅ Apply Kubernetes labels and taints
- ✅ Create single-AZ machine pools in multi-AZ clusters
- ✅ Enable Secure Boot for Shielded VMs
- ✅ Full lifecycle management (create, update, delete)

## Prerequisites

- OCM CLI installed and authenticated (`ocm login`)
- An existing OSD cluster on GCP
- Terraform >= 1.0

## Usage

### Basic Machine Pool

```hcl
module "worker_pool" {
  source = "./modules/machine-pool"

  cluster_id        = "your-cluster-id"
  machine_pool_name = "worker-pool-1"
  instance_type     = "n2-standard-8"
  replicas          = 3
}
```

### Machine Pool with Autoscaling

```hcl
module "autoscaling_pool" {
  source = "./modules/machine-pool"

  cluster_id        = "your-cluster-id"
  machine_pool_name = "auto-pool"
  instance_type     = "n2-standard-4"
  
  enable_autoscaling = true
  min_replicas       = 2
  max_replicas       = 10
}
```

### GPU Machine Pool with Labels and Taints

```hcl
module "gpu_pool" {
  source = "./modules/machine-pool"

  cluster_id        = "your-cluster-id"
  machine_pool_name = "gpu-nodes"
  instance_type     = "a2-highgpu-1g"
  replicas          = 2

  labels = {
    "workload-type" = "gpu"
    "team"          = "ml"
  }

  taints = [
    {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NoSchedule"
    }
  ]
}
```

### Single-AZ Machine Pool in Multi-AZ Cluster

```hcl
module "zone_a_pool" {
  source = "./modules/machine-pool"

  cluster_id        = "your-cluster-id"
  machine_pool_name = "zone-a"
  instance_type     = "n2-standard-4"
  replicas          = 3
  availability_zone = "us-central1-a"
}
```

### Memory-Optimized Pool with Secure Boot

```hcl
module "memory_pool" {
  source = "./modules/machine-pool"

  cluster_id          = "your-cluster-id"
  machine_pool_name   = "memory-opt"
  instance_type       = "n2-highmem-8"
  replicas            = 4
  secure_boot_enabled = true

  labels = {
    "node.kubernetes.io/memory" = "high"
  }
}
```

## Multiple Machine Pools

You can create multiple machine pools by calling the module multiple times:

```hcl
# General purpose workers
module "general_pool" {
  source = "./modules/machine-pool"

  cluster_id        = local.cluster_id
  machine_pool_name = "general"
  instance_type     = "n2-standard-4"
  replicas          = 6
}

# High-memory workers
module "memory_pool" {
  source = "./modules/machine-pool"

  cluster_id        = local.cluster_id
  machine_pool_name = "highmem"
  instance_type     = "n2-highmem-8"
  replicas          = 3

  labels = {
    "workload" = "memory-intensive"
  }
}

# GPU workers
module "gpu_pool" {
  source = "./modules/machine-pool"

  cluster_id        = local.cluster_id
  machine_pool_name = "gpu"
  instance_type     = "a2-highgpu-1g"
  replicas          = 2

  taints = [
    {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NoSchedule"
    }
  ]
}
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `cluster_id` | OCM cluster ID or name | `string` | - | yes |
| `machine_pool_name` | Name of the machine pool (2-15 chars, lowercase) | `string` | - | yes |
| `instance_type` | GCP instance type | `string` | - | yes |
| `enable_autoscaling` | Enable autoscaling | `bool` | `false` | no |
| `replicas` | Number of replicas (when not autoscaling) | `number` | `null` | no |
| `min_replicas` | Minimum replicas (when autoscaling) | `number` | `null` | no |
| `max_replicas` | Maximum replicas (when autoscaling) | `number` | `null` | no |
| `labels` | Kubernetes labels | `map(string)` | `{}` | no |
| `taints` | Kubernetes taints | `list(object)` | `[]` | no |
| `availability_zone` | Specific AZ for single-AZ pool | `string` | `""` | no |
| `secure_boot_enabled` | Enable Secure Boot | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| `machine_pool_id` | The ID/name of the machine pool |
| `cluster_id` | The cluster ID |
| `instance_type` | The instance type used |
| `replicas` | Number of replicas |
| `autoscaling` | Autoscaling configuration |
| `labels` | Applied labels |
| `taints` | Applied taints |
| `availability_zone` | The availability zone |

## GCP Instance Types

Common instance types for OSD on GCP:

| Instance Type | vCPU | Memory | Use Case |
|--------------|------|--------|----------|
| `custom-4-32768-ext` | 4 | 32GB | Default for OSD |
| `n2-standard-4` | 4 | 16GB | General purpose |
| `n2-standard-8` | 8 | 32GB | General purpose |
| `n2-standard-16` | 16 | 64GB | High performance |
| `n2-highmem-4` | 4 | 32GB | Memory-optimized |
| `n2-highmem-8` | 8 | 64GB | Memory-optimized |
| `n2-highmem-16` | 16 | 128GB | Memory-optimized |
| `c2-standard-4` | 4 | 16GB | Compute-optimized |
| `c2-standard-8` | 8 | 32GB | Compute-optimized |
| `a2-highgpu-1g` | 12 | 85GB | GPU (1x A100) |
| `a2-highgpu-2g` | 24 | 170GB | GPU (2x A100) |

## Notes

1. **Default Machine Pool**: The default "worker" machine pool created with the cluster cannot be deleted or renamed. Use this module for additional pools only.

2. **Labels and Taints**: Labels and taints set through this module will overwrite any manual modifications made directly on the nodes.

3. **Multi-AZ Replicas**: For multi-AZ clusters without `availability_zone` set, replicas are distributed across zones. It's recommended to use replica counts that are multiples of the zone count.

4. **Instance Type Changes**: Changing the `instance_type` will trigger recreation of the machine pool, which involves node drain and new node provisioning.
