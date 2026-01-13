# OSD GCP Machine Pool Module

Creates additional machine pools for OpenShift Dedicated clusters on GCP.

## Usage

### Basic Pool (Fixed Replicas)

```hcl
module "large_pool" {
  source = "./modules/machine-pool"

  cluster_name  = "my-cluster"
  name          = "large"
  instance_type = "n2-standard-16"
  replicas      = 3
  
  labels = {
    "workload-type" = "large"
  }
}
```

### Autoscaling Pool

```hcl
module "autoscale_pool" {
  source = "./modules/machine-pool"

  cluster_name  = "my-cluster"
  name          = "autoscale"
  instance_type = "n2-standard-8"
  
  autoscaling = {
    enabled      = true
    min_replicas = 1
    max_replicas = 10
  }
}
```

### Single-Zone Pool in Multi-AZ Cluster

```hcl
module "zone_a_pool" {
  source = "./modules/machine-pool"

  cluster_name      = "my-cluster"
  name              = "zone-a"
  instance_type     = "n2-standard-4"
  replicas          = 2
  availability_zone = "us-central1-a"
}
```

### Pool with Taints

```hcl
module "gpu_pool" {
  source = "./modules/machine-pool"

  cluster_name  = "my-cluster"
  name          = "gpu"
  instance_type = "a2-highgpu-1g"
  replicas      = 1
  availability_zone = "us-central1-a"
  
  labels = {
    "workload-type" = "gpu"
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

## Multi-AZ Considerations

For multi-AZ clusters (e.g., 3 zones):
- **Distributed pool**: Set `replicas` to multiple of zone count (3, 6, 9...)
- **Single-zone pool**: Set any `replicas` + specify `availability_zone`

## Variables

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `cluster_name` | string | Yes | OSD cluster name |
| `name` | string | Yes | Machine pool name |
| `instance_type` | string | Yes | GCP instance type |
| `replicas` | number | No | Node count (default: 1) |
| `autoscaling` | object | No | Autoscaling config |
| `labels` | map(string) | No | Node labels |
| `taints` | list(object) | No | Node taints |
| `availability_zone` | string | No | Specific AZ for single-zone pool |

## Outputs

| Name | Description |
|------|-------------|
| `name` | Machine pool name |
| `instance_type` | Instance type |
| `replicas` | Replica count |
