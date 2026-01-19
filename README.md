# OpenShift Dedicated on GCP - Terraform Automation

Terraform automation for deploying OpenShift Dedicated (OSD) clusters on Google Cloud Platform with support for:
- **Public clusters** - Standard deployment with public endpoints
- **Private clusters** - No public endpoints, bastion access required
- **Private Service Connect (PSC)** - Enhanced private connectivity using GCP PSC
- **Hub-Spoke architecture** - Fully private VPC with proxy-based egress through a landing zone

## Architecture

### Standard Private Cluster
```
┌─────────────────────────────────────────────────────────────┐
│                     OSD VPC                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Masters   │  │   Workers   │  │  PSC (Google APIs)  │ │
│  │ 10.x.x.x/27 │  │ 10.x.x.x/19 │  │    10.x.x.x/29      │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│                         │                                   │
│                    Cloud NAT ────► Internet                 │
└─────────────────────────────────────────────────────────────┘
```

### Hub-Spoke Architecture (Fully Private)
```
┌────────────────────────┐         ┌─────────────────────────┐
│ Landing Zone VPC (Hub) │         │    OSD VPC (Spoke)      │
│                        │         │                         │
│  ┌─────────────────┐   │  Peer   │  ┌─────────┐ ┌────────┐│
│  │ Squid Proxy/    │◄──┼─────────┼─►│ Masters │ │Workers ││
│  │ Bastion         │   │         │  └─────────┘ └────────┘│
│  └────────┬────────┘   │         │                         │
│           │            │         │  ┌──────────────────┐  │
│  ┌────────▼────────┐   │         │  │ PSC (Google APIs)│  │
│  │ Cloud NAT       │   │         │  └──────────────────┘  │
│  └────────┬────────┘   │         │                         │
│           ▼            │         │  (No NAT - uses proxy)  │
│       Internet         │         │                         │
└────────────────────────┘         └─────────────────────────┘
```

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **OCM CLI** >= 1.0.3 (>= 0.1.73 for PSC support)
- **gcloud CLI** - authenticated
- **jq** - JSON processor

### GCP Setup
1. Create a GCP project with billing enabled
2. Enable required APIs:
   ```bash
   gcloud services enable compute.googleapis.com \
       container.googleapis.com \
       dns.googleapis.com \
       iap.googleapis.com \
       cloudresourcemanager.googleapis.com
   ```
3. Follow the [Required customer procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure_gcp-ccs)

### OCM Authentication
```bash
# Login to OCM
ocm login --token=<your-token>

# Get token from: https://console.redhat.com/openshift/token
```

Optional: you can also provide `ocm_token` in `terraform.tfvars` to let Terraform
perform a non-interactive login before cluster creation.

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd terraform-google-osd

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 2. Required Configuration

At minimum, set these values in `terraform.tfvars`:

```hcl
# GCP Settings
gcp_project = "your-gcp-project-id"
gcp_region  = "us-central1"
gcp_zone    = "us-central1-a"

# Cluster Settings
clustername = "my-osd-cluster"

# Authentication (WIF recommended)
gcp_authentication_type = "workload_identity_federation"

# Network CIDRs (all must be within machine_cidr)
machine_cidr          = "10.0.0.0/16"
master_cidr_block     = "10.0.0.0/19"
worker_cidr_block     = "10.0.32.0/19"
psc_subnet_cidr_block = "10.0.64.0/29"
bastion_cidr_block    = "10.10.0.0/24"
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy
terraform apply
```

## Configuration Options

### GCP Settings

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `gcp_project` | string | Yes | - | GCP Project ID |
| `gcp_region` | string | Yes | - | GCP Region (e.g., us-central1) |
| `gcp_zone` | string | Yes | - | GCP Zone (e.g., us-central1-a) |

### Cluster Settings

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `clustername` | string | Yes | - | Cluster name (used as resource prefix) |
| `cluster_version` | string | No | "" | OpenShift version (e.g., "4.14"). Empty = latest |
| `compute_nodes_count` | number | No | null | Number of worker nodes. For multi-AZ, must be multiple of zone count |
| `compute_machine_type` | string | No | "" | Worker node instance type (e.g., n2-standard-8) |
| `domain_prefix` | string | No | "" | Custom domain prefix for cluster URLs |

### Authentication

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `gcp_authentication_type` | string | Yes | - | `workload_identity_federation` or `service_account` |
| `gcp_sa_file_loc` | string | No | - | Path to SA JSON (required for service_account auth) |
| `use_existing_wif` | bool | No | false | Use existing WIF config instead of creating new |
| `existing_wif_config_name` | string | No | "" | Name of existing WIF config |

### Network Configuration

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `machine_cidr` | string | Yes | "" | Overall IP range for cluster (e.g., 10.0.0.0/16) |
| `master_cidr_block` | string | Yes | - | Control plane subnet CIDR |
| `worker_cidr_block` | string | Yes | - | Worker subnet CIDR |
| `psc_subnet_cidr_block` | string | Yes | - | PSC subnet CIDR (/29 or larger) |
| `bastion_cidr_block` | string | Yes | - | Bastion subnet CIDR |
| `vpc_routing_mode` | string | No | "REGIONAL" | VPC routing mode |

### Existing VPC (BYO VPC)

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `use_existing_vpc` | bool | No | false | Use pre-existing VPC |
| `existing_vpc_name` | string | No | "" | Name of existing VPC |
| `existing_master_subnet_name` | string | No | "" | Name of existing master subnet |
| `existing_worker_subnet_name` | string | No | "" | Name of existing worker subnet |
| `existing_psc_subnet_name` | string | No | "" | Name of existing PSC subnet |
| `existing_router_name` | string | No | "" | Name of existing Cloud Router |

### Cluster Type

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `osd_gcp_private` | bool | No | false | Deploy as private cluster |
| `osd_gcp_psc` | bool | No | false | Enable Private Service Connect |
| `psc_endpoint_address` | string | No | - | IP for PSC Google APIs endpoint |
| `enable_nat_gateway` | bool | No | true | Create NAT gateway (false for hub-spoke) |

### Multi-AZ Configuration

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `gcp_availability_zones` | string | No | "" | Comma-separated zones (e.g., "us-central1-a,us-central1-b,us-central1-c") |

### Proxy Configuration (Hub-Spoke)

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `http_proxy` | string | No | "" | HTTP proxy URL (e.g., http://10.100.0.10:3128) |
| `https_proxy` | string | No | "" | HTTPS proxy URL |
| `no_proxy` | string | No | "" | Domains/CIDRs to bypass proxy |
| `additional_trust_bundle` | string | No | "" | Path to CA bundle for proxy |

### Bastion Host

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `enable_osd_gcp_bastion` | bool | No | false | Deploy bastion host |
| `bastion_machine_type` | string | No | "e2-micro" | Bastion instance type |
| `bastion_key_loc` | string | No | "~/.ssh/id_rsa.pub" | SSH public key path |

### Additional Machine Pools

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `additional_machine_pools` | list(object) | No | [] | Additional machine pool configurations |

Example:
```hcl
additional_machine_pools = [
  {
    name          = "large"
    instance_type = "n2-standard-16"
    replicas      = 2
    labels = {
      "workload-type" = "large"
    }
  },
  {
    name          = "gpu"
    instance_type = "n1-standard-4"
    min_replicas  = 1
    max_replicas  = 5
    taints = [
      {
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NoSchedule"
      }
    ]
  }
]
```

### Advanced Options

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `only_deploy_infra_no_osd` | bool | No | false | Deploy only infrastructure, skip cluster |

## Deployment Scenarios

### Scenario 1: Public Cluster (Simplest)

```hcl
gcp_project             = "my-project"
clustername             = "my-cluster"
gcp_region              = "us-central1"
gcp_zone                = "us-central1-a"
gcp_authentication_type = "workload_identity_federation"

machine_cidr          = "10.0.0.0/16"
master_cidr_block     = "10.0.0.0/19"
worker_cidr_block     = "10.0.32.0/19"
psc_subnet_cidr_block = "10.0.64.0/29"
bastion_cidr_block    = "10.10.0.0/24"

osd_gcp_private = false
osd_gcp_psc     = false
```

### Scenario 2: Private Cluster with PSC

```hcl
gcp_project             = "my-project"
clustername             = "my-private-cluster"
gcp_region              = "us-central1"
gcp_zone                = "us-central1-a"
gcp_authentication_type = "workload_identity_federation"

machine_cidr          = "10.0.0.0/16"
master_cidr_block     = "10.0.0.0/19"
worker_cidr_block     = "10.0.32.0/19"
psc_subnet_cidr_block = "10.0.64.0/29"
psc_endpoint_address  = "10.0.100.100"
bastion_cidr_block    = "10.10.0.0/24"

osd_gcp_private        = true
osd_gcp_psc            = true
enable_osd_gcp_bastion = true
```

### Scenario 3: Multi-AZ Private Cluster

```hcl
gcp_project              = "my-project"
clustername              = "my-multiaz-cluster"
gcp_region               = "us-central1"
gcp_zone                 = "us-central1-a"
gcp_authentication_type  = "workload_identity_federation"
gcp_availability_zones   = "us-central1-a,us-central1-b,us-central1-c"
compute_nodes_count      = 3  # Must be multiple of zone count

machine_cidr          = "10.0.0.0/16"
master_cidr_block     = "10.0.0.0/19"
worker_cidr_block     = "10.0.32.0/19"
psc_subnet_cidr_block = "10.0.64.0/29"
psc_endpoint_address  = "10.0.100.100"
bastion_cidr_block    = "10.10.0.0/24"

osd_gcp_private        = true
osd_gcp_psc            = true
enable_osd_gcp_bastion = true
```

### Scenario 4: Hub-Spoke with Proxy (Fully Private)

First, run the setup script to create the infrastructure:

```bash
./scripts/setup-vpc-infrastructure.sh -p my-project -r us-central1 -c my-cluster
```

Then configure terraform.tfvars:

```hcl
gcp_project             = "my-project"
clustername             = "my-cluster"
gcp_region              = "us-central1"
gcp_zone                = "us-central1-a"
gcp_authentication_type = "workload_identity_federation"

# Use VPC created by setup script
use_existing_vpc            = true
existing_vpc_name           = "my-cluster-vpc"
existing_master_subnet_name = "my-cluster-master-subnet"
existing_worker_subnet_name = "my-cluster-worker-subnet"
existing_psc_subnet_name    = "my-cluster-psc-subnet"
existing_router_name        = "my-cluster-router"

# CIDRs matching script (10.92.x.x range)
machine_cidr          = "10.92.0.0/16"
master_cidr_block     = "10.92.0.0/27"
worker_cidr_block     = "10.92.32.0/19"
psc_subnet_cidr_block = "10.92.64.0/29"
psc_endpoint_address  = "10.92.100.100"
bastion_cidr_block    = "10.10.0.0/24"

# No NAT - using proxy
enable_nat_gateway = false

# Proxy in landing zone VPC
http_proxy  = "http://10.100.0.10:3128"
https_proxy = "http://10.100.0.10:3128"
no_proxy    = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.169.254"

osd_gcp_private        = true
osd_gcp_psc            = true
enable_osd_gcp_bastion = false  # Bastion is in landing zone
```

### Scenario 5: Using Existing WIF

```hcl
gcp_authentication_type  = "workload_identity_federation"
use_existing_wif         = true
existing_wif_config_name = "my-existing-wif"
```

## Accessing Private Clusters

### Via Bastion (Standard)

```bash
# SSH to bastion
gcloud compute ssh ${CLUSTERNAME}-bastion-vm \
  --zone=${GCP_ZONE} \
  --project=${GCP_PROJECT}

# Or via IAP tunnel
gcloud compute ssh ${CLUSTERNAME}-bastion-vm \
  --zone=${GCP_ZONE} \
  --project=${GCP_PROJECT} \
  --tunnel-through-iap
```

### Via Landing Zone Proxy (Hub-Spoke)

After cluster deployment, configure DNS peering:

```bash
./scripts/setup-vpc-infrastructure.sh -p my-project -r us-central1 -c my-cluster --configure-dns
```

Then SSH to the proxy:

```bash
gcloud compute ssh landing-zone-proxy \
  --zone=${GCP_ZONE}-a \
  --project=${GCP_PROJECT} \
  --tunnel-through-iap
```

### Cluster Login

```bash
# Configure IdP first at https://console.redhat.com

# Login to cluster
oc login https://api.${CLUSTERNAME}.${DOMAIN}.openshiftapps.com:6443 \
  --username=<your-username> \
  --password=<your-password>

# Verify access
oc get nodes
oc get clusterversion
```

## Cleanup

```bash
# Destroy cluster and infrastructure
terraform destroy

# For hub-spoke: Also cleanup landing zone
./scripts/setup-vpc-infrastructure.sh -p my-project -r us-central1 -c my-cluster --delete
```

## Directory Structure

```
terraform-google-osd/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── terraform.tfvars           # Your configuration (gitignored)
├── terraform.tfvars.example   # Example configuration
├── modules/
│   ├── vpc/                   # VPC, subnets, router, NAT
│   ├── psc/                   # Private Service Connect resources
│   ├── bastion/               # Bastion host
│   └── machine-pool/          # Additional machine pools
├── templates/
│   ├── clusterinstall.tftpl   # Cluster installation script
│   ├── clusterdestroy.tftpl   # Cluster destruction script
│   └── wif*.tftpl             # WIF management scripts
├── scripts/
│   ├── setup-vpc-infrastructure.sh  # Hub-spoke VPC setup
│   └── check-prereqs.sh       # Prerequisites checker
├── assets/                    # Architecture diagrams
├── state/                     # Local state files (gitignored)
└── output/                    # Plan files (gitignored)
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Subnet CIDR outside machine CIDR | Mismatched CIDRs | Ensure all subnets are within `machine_cidr` |
| OCM session expired | Token expired | Run `ocm login --token=<token>` |
| Can't reach API from bastion | Firewall/DNS | Check firewall rules, verify DNS resolution |
| Cluster stuck in installing | Various | Check OCM console for detailed errors |
| PSC validation failed | Wrong CIDR ranges | Ensure PSC subnet is within machine CIDR |

### Checking Cluster Status

```bash
# Via OCM CLI
ocm get /api/clusters_mgmt/v1/clusters --parameter search="name = 'my-cluster'" | \
  jq '.items[0] | {name, state, status: .status.description}'

# Via OCM console
# https://console.redhat.com/openshift
```

### Logs and Debugging

```bash
# Terraform debug
TF_LOG=DEBUG terraform apply

# OCM debug
ocm get /api/clusters_mgmt/v1/clusters/<cluster-id> | jq '.status'
```

## References

- [OSD on GCP Documentation](https://docs.openshift.com/dedicated/osd_install_access_delete_cluster/creating-a-gcp-cluster.html)
- [Private Service Connect](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-psc-enabled-private-cluster.html)
- [Workload Identity Federation](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-cluster-with-workload-identity-federation.html)
- [GCP CCS Prerequisites](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html)
- [PSC Firewall Prerequisites](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html-single/planning_your_environment/index#osd-gcp-psc-firewall-prerequisites_gcp-ccs)

## License

Apache 2.0
