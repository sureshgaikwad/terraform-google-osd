variable "gcp_region" {
  type        = string
  description = "The target GCP region for the cluster."
}

variable "gcp_zone" {
  type        = string
  description = "The target GCP zone for the cluster."
}

variable "gcp_project" {
  type        = string
  description = "The target GCP project for the cluster."
}

variable "vpc_routing_mode" {
  type        = string
  description = "The network-wide routing mode to use."
}

variable "clustername" {
  type        = string
  description = "The name of the cluster."
}

# ============================================
# Existing VPC Configuration
# ============================================

variable "use_existing_vpc" {
  type        = bool
  description = <<EOF
Whether to use an existing VPC or create a new one.

Set to false (default): Terraform creates a new VPC and all subnets.
Set to true: Use existing VPC and subnets specified by the existing_* variables.

When using existing VPC, you must also set:
  - existing_vpc_name
  - existing_master_subnet_name
  - existing_worker_subnet_name
  - existing_psc_subnet_name (if osd_gcp_psc = true)
  - existing_router_name (optional, for NAT gateway)
EOF
  default     = false
}

variable "existing_vpc_name" {
  type        = string
  description = <<EOF
Name of the existing VPC to use. Required when use_existing_vpc = true.
Example: "my-existing-vpc"
EOF
  default     = ""
}

variable "existing_master_subnet_name" {
  type        = string
  description = <<EOF
Name of the existing master/control-plane subnet. Required when use_existing_vpc = true.
The subnet must have private_ip_google_access enabled.
Example: "my-master-subnet"
EOF
  default     = ""
}

variable "existing_worker_subnet_name" {
  type        = string
  description = <<EOF
Name of the existing worker/compute subnet. Required when use_existing_vpc = true.
The subnet must have private_ip_google_access enabled.
Example: "my-worker-subnet"
EOF
  default     = ""
}

variable "existing_psc_subnet_name" {
  type        = string
  description = <<EOF
Name of the existing PSC subnet. Required when use_existing_vpc = true AND osd_gcp_psc = true.
The subnet must have purpose = PRIVATE_SERVICE_CONNECT.
Example: "my-psc-subnet"
EOF
  default     = ""
}

variable "existing_router_name" {
  type        = string
  description = <<EOF
Name of the existing Cloud Router. Optional when use_existing_vpc = true.
If not specified and enable_nat_gateway = true, a new router will be created.
Example: "my-router"
EOF
  default     = ""
}


variable "master_cidr_block" {
  type        = string
  description = <<EOF
The IP address space from which to assign machine IPs.
Default "10.0.0.0/17"
EOF
  default     = "10.0.0.0/17"
}

variable "worker_cidr_block" {
  type        = string
  description = <<EOF
The IP address space from which to assign machine IPs.
Default "10.0.128.0/17"
EOF
  default     = "10.0.128.0/17"
}

variable "bastion_cidr_block" {
  type        = string
  description = <<EOF
The IP address space from which to deploy the bastion / jumphost.
Default "10.0.128.0/17"
EOF
  default     = "10.0.128.0/17"
}

variable "enable_osd_gcp_bastion" {
  description = <<EOF
If set to true, deploy a bastion in the OSD in GCP private subnet. 
Variable osd_gcp_private needs to be enabled."
EOF
  type        = bool
  default     = false
}

variable "osd_gcp_private" {
  description = "If set to true, deploy a second vpc/network for a OSD in GCP private install"
  type        = bool
  default     = false
}

variable "bastion_machine_type" {
  type        = string
  description = <<EOF
The Machine Type from for our Bastion.
Default "e2-micro"
EOF
  default     = "e2-micro"
}

variable "bastion_key_loc" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Public key for bastion host"
}

variable "gcp_sa_file_loc" {
  type        = string
  default     = "~/.ssh/id_rsa_sa.json"
  description = "Path to private json for OSD on GCP Admin Service Account"
}

variable "only_deploy_infra_no_osd" {
  description = "If set to true, only the networking infra will be deployed, not the OSD in GCP cluster"
  type        = bool
  default     = false
}

variable "gcp_authentication_type" {
  description = "How the installer and cluster should authenticate with GCP. Either 'service_account' or 'workload_identity_federation'"
  type        = string
  default     = "service_account"
  validation {
    condition     = contains(["service_account", "workload_identity_federation"], var.gcp_authentication_type)
    error_message = "Valid values for gcp_authentication_type are either 'service_account' or workload_identity_federation'."
  }
}

variable "use_existing_wif" {
  type        = bool
  description = <<EOF
Whether to use an existing WIF configuration or create a new one.

Set to false (default): Terraform creates a new WIF config named "<clustername>-wif".
Set to true: Use existing WIF config specified by existing_wif_config_name.

When using existing WIF, ensure:
  - The WIF config exists and is valid
  - It is configured for the correct GCP project
EOF
  default     = false
}

variable "existing_wif_config_name" {
  type        = string
  description = <<EOF
Name of the existing WIF configuration to use. Required when use_existing_wif = true.
Example: "my-existing-wif"

To list existing WIF configs: ocm gcp list wif-configs
EOF
  default     = ""
}

variable "osd_gcp_psc" {
  description = "If set to true, deploy OSD with Private Service Connect (PSC) enabled"
  type        = bool
  default     = false
}

variable "psc_subnet_cidr_block" {
  type        = string
  description = <<EOF
The IP address space for PSC endpoints subnet.
Must be /29 or larger and within the Machine CIDR range.
Default "10.0.0.248/29"
EOF
  default     = "10.0.0.248/29"  
}

variable "psc_endpoint_address" {
  type        = string
  description = <<EOF
The IP address for the PSC Google APIs endpoint.
Must be within your Machine CIDR range but outside all subnets.
Example: If your subnets are in 10.92.x.x, use something like "10.92.255.100"
EOF
  default     = "10.0.255.100"
}

variable "enable_psc_endpoints" {
  description = "List of GCP services to create PSC endpoints for"
  type        = list(string)
  default     = [
    "storage.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com"
  ]
}

variable "gcp_availability_zones" {
  type        = string
  description = <<EOF
Comma-separated list of GCP availability zones for multi-AZ deployment.
Example: "us-west1-a,us-west1-b,us-west1-c"
If not specified, cluster will be deployed in single zone (gcp_zone).
For multi-AZ, typically use 3 zones and ensure compute-nodes is multiple of 3.
EOF
  default     = ""
}

variable "enable_nat_gateway" {
  type        = bool
  description = <<EOF
Whether to create NAT gateways for internet connectivity.

Set to true (default): Creates Cloud NAT for master and worker subnets.
                       Use for standalone deployments with direct internet access.

Set to false: No NAT gateways created. VPC is completely private.
              Use when internet connectivity is provided via a landing zone
              (hub-spoke architecture) or other network topology.

IMPORTANT: When set to false, the following prerequisites must be met:
  - Network connectivity to Red Hat container registries must be preconfigured
    (registry.redhat.io, quay.io, registry.connect.redhat.com)
  - Network connectivity to OCM API (api.openshift.com) must be available
  - This is typically achieved through VPC peering to a landing zone,
    Shared VPC, VPN, or Cloud Interconnect with appropriate routing.
EOF
  default     = true
}

variable "compute_nodes_count" {
  type        = number
  description = <<EOF
Number of worker/compute nodes to provision.
For single-zone clusters: minimum 2 nodes on CCS, 4 on Red Hat infra.
For multi-AZ clusters: minimum 3 nodes on CCS (1 per zone), 9 on Red Hat infra (3 per zone).
Multi-AZ requires compute nodes to be a multiple of the number of zones.
If not specified, defaults to minimum required based on deployment type (9 for multi-AZ, OCM default for single-AZ).
EOF
  default     = null
  validation {
    condition     = try(var.compute_nodes_count == null, false) || try(var.compute_nodes_count > 0, true)
    error_message = "compute_nodes_count must be a positive number if specified."
  }
}

# ============================================
# Proxy Configuration (for private VPC without NAT)
# ============================================

variable "http_proxy" {
  type        = string
  description = <<EOF
HTTP proxy URL for cluster egress traffic.
Required when deploying to a private VPC without NAT gateway.
Format: http://<proxy-ip>:<port>
Example: http://10.100.0.10:3128
EOF
  default     = ""
}

variable "https_proxy" {
  type        = string
  description = <<EOF
HTTPS proxy URL for cluster egress traffic.
Required when deploying to a private VPC without NAT gateway.
Format: http://<proxy-ip>:<port> (note: still uses http:// scheme)
Example: http://10.100.0.10:3128
EOF
  default     = ""
}

variable "no_proxy" {
  type        = string
  description = <<EOF
Comma-separated list of CIDRs to bypass the proxy.
Note: OCM only accepts valid CIDRs or full domain names (not .svc or .cluster.local).
Required when http_proxy or https_proxy is set.
Example: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.169.254"
EOF
  default     = ""
}

variable "additional_trust_bundle" {
  type        = string
  description = <<EOF
Path to a PEM-encoded CA certificate bundle for the proxy.
Only required if the proxy uses a custom/self-signed certificate.
EOF
  default     = ""
}

variable "domain_prefix" {
  type        = string
  description = <<EOF
Custom domain prefix for the cluster.
This sets the first part of your cluster's domain name.
Example: If you set "myapp", your cluster URL will be:
  https://api.myapp.<random>.p1.openshiftapps.com
If not set, OCM uses the cluster name as prefix.
EOF
  default     = ""
}

variable "compute_machine_type" {
  type        = string
  description = <<EOF
Instance type for the compute (worker) nodes.
Determines the amount of memory and vCPU allocated to each compute node.
Examples for GCP:
  - custom-4-32768-ext   (4 vCPU, 32GB RAM) - Default for OSD
  - n2-standard-4        (4 vCPU, 16GB RAM)
  - n2-standard-8        (8 vCPU, 32GB RAM)
  - n2-highmem-4         (4 vCPU, 32GB RAM)
  - e2-standard-4        (4 vCPU, 16GB RAM)
Run `ocm list machine-types --provider gcp` to see available types.
If not set, OCM uses the default instance type.
EOF
  default     = ""
}

# ============================================
# Additional Machine Pools Configuration
# ============================================

variable "additional_machine_pools" {
  description = <<EOF
Additional machine pools to create after cluster installation.
The default "worker" pool is created during cluster installation.
These pools are created AFTER the cluster is ready.

Each pool object supports:
  - name          : (Required) Name of the machine pool
  - instance_type : (Required) GCP instance type (e.g., n2-standard-8)
  - replicas      : (Optional) Fixed number of nodes (mutually exclusive with autoscaling)
  - min_replicas  : (Optional) Minimum nodes for autoscaling
  - max_replicas  : (Optional) Maximum nodes for autoscaling
  - labels        : (Optional) Map of labels to apply to nodes
  - taints        : (Optional) List of taints to apply to nodes
  - availability_zone : (Optional) Single zone for this pool (multi-AZ clusters only)

Example:
  additional_machine_pools = [
    {
      name          = "large"
      instance_type = "n2-standard-16"
      replicas      = 2
      labels        = { "workload-type" = "large" }
    },
    {
      name          = "gpu"
      instance_type = "n1-standard-4"
      min_replicas  = 1
      max_replicas  = 5
      labels        = { "workload-type" = "gpu" }
    }
  ]
EOF
  type = list(object({
    name              = string
    instance_type     = string
    replicas          = optional(number, null)
    min_replicas      = optional(number, null)
    max_replicas      = optional(number, null)
    labels            = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    availability_zone = optional(string, null)
  }))
  default = []
}
