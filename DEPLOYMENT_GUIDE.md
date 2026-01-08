# Step-by-Step Guide: Deploy OpenShift Dedicated on Google Cloud with Terraform

This guide provides detailed instructions for deploying OpenShift Dedicated (OSD) on Google Cloud Platform (GCP) using Terraform.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Authentication Setup](#authentication-setup)
3. [Configuration](#configuration)
4. [Deployment](#deployment)
5. [Post-Deployment](#post-deployment)
6. [Cleanup](#cleanup)

---

## Prerequisites

### 1. Required Software Installation

Install the following tools on your local machine:

#### OCM CLI (OpenShift Cluster Manager)
- **Minimum version**: 0.1.73 (required for PSC support)
- **Installation**:
  ```bash
  # Download OCM CLI
  wget https://github.com/openshift-online/ocm-cli/releases/download/v0.1.73/ocm-linux-amd64
  # For macOS:
  wget https://github.com/openshift-online/ocm-cli/releases/download/v0.1.73/ocm-darwin-amd64
  
  # Make executable and move to PATH
  chmod +x ocm-linux-amd64  # or ocm-darwin-amd64
  sudo mv ocm-linux-amd64 /usr/local/bin/ocm  # or ocm-darwin-amd64
  ```

#### Terraform
- **Minimum version**: 0.14
- **Installation**: Follow [Terraform installation guide](https://www.terraform.io/downloads)

#### Google Cloud SDK (gcloud)
- **Installation**: Follow [gcloud installation guide](https://cloud.google.com/sdk/docs/install)

#### jq
- **Installation**:
  ```bash
  # macOS
  brew install jq
  
  # Linux
  sudo apt-get install jq  # Debian/Ubuntu
  sudo yum install jq      # RHEL/CentOS
  ```

### 2. GCP Account Setup

1. **Create a GCP Project** (if you don't have one):
   ```bash
   gcloud projects create YOUR_PROJECT_ID --name="Your Project Name"
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Enable Required APIs**:
   ```bash
   gcloud services enable \
     compute.googleapis.com \
     container.googleapis.com \
     dns.googleapis.com \
     servicenetworking.googleapis.com \
     cloudresourcemanager.googleapis.com
   ```

3. **Authenticate with GCP**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

### 3. Red Hat OpenShift Account Setup

1. **Create a Red Hat account** at https://www.redhat.com/account
2. **Subscribe to OpenShift Dedicated** service
3. **Login to OCM**:
   ```bash
    
   # Follow the browser authentication flow
   ```

4. **Verify OCM connection**:
   ```bash
   ocm whoami
   ocm list clusters
   ```

---

## Authentication Setup

Choose one of two authentication methods:

### Option A: Workload Identity Federation (Recommended)

**Workload Identity Federation** uses short-lived credentials and is the preferred method.

#### Steps:

1. **Follow Red Hat Documentation**:
   - General procedure: [Required customer procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure_gcp-ccs)
   - WIF-specific: [Workload Identity Federation procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure-wif_gcp-ccs)

2. **Set Environment Variable**:
   ```bash
   export TF_VAR_gcp_authentication_type=workload_identity_federation
   ```

3. **Optional: Set SSH Key Location** (if not using default):
   ```bash
   export TF_VAR_bastion_key_loc=~/.ssh/id_rsa.pub
   ```

### Option B: Service Account

**Service Account** authentication uses a public/private keypair with broader permissions.

#### Steps:

1. **Follow Red Hat Documentation**:
   - General procedure: [Required customer procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure_gcp-ccs)
   - SA-specific: [Service account procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure-sa_gcp-ccs)

2. **Create Service Account Key**:
   - Download the `osd-ccs-admin` service account JSON key file
   - Save it securely (e.g., `~/.gcp/osd-ccs-admin.json`)

3. **Set Environment Variables**:
   ```bash
   export TF_VAR_gcp_sa_file_loc=~/.gcp/osd-ccs-admin.json
   export TF_VAR_gcp_authentication_type=service_account
   ```

4. **Optional: Set SSH Key Location** (if not using default):
   ```bash
   export TF_VAR_bastion_key_loc=~/.ssh/id_rsa.pub
   ```

---

## Configuration

### Step 1: Choose Deployment Scenario

This repository supports three deployment scenarios:

#### Scenario 1: Standard OSD in Pre-Existing VPC
- Use existing VPC/subnets
- Public cluster access

#### Scenario 2: OSD with Full Infrastructure (Recommended for New Deployments)
- Terraform creates VPC, subnets, NAT gateways
- Can be public or private

#### Scenario 3: OSD with Private Service Connect (PSC)
- Fully private cluster
- Enhanced security
- Requires OpenShift 4.17+

#### Scenario 4: Multi-Availability Zone (Multi-AZ) Deployment
- High availability across multiple zones
- Enhanced resilience and fault tolerance
- Recommended for production workloads
- Can be combined with private cluster or PSC

### Step 2: Configure Terraform Variables

#### For Standard Deployment:

```bash
# Copy the example configuration
cp configuration/tfvars/terraform.tfvars.example configuration/tfvars/terraform.tfvars
```

Edit `configuration/tfvars/terraform.tfvars` with your values:

```hcl
gcp_project = "your-gcp-project-id"
clustername = "your-cluster-name"
vpc_routing_mode = "REGIONAL"
master_cidr_block = "10.0.0.0/17"
worker_cidr_block = "10.0.128.0/17"
gcp_region = "us-west1"
gcp_zone = "us-west1-a"
gcp_authentication_type = "workload_identity_federation"  # or "service_account"
```

#### For Private Cluster:

Add these to your `terraform.tfvars`:

```hcl
osd_gcp_private = true
enable_osd_gcp_bastion = true
bastion_cidr_block = "10.10.0.0/24"
bastion_machine_type = "e2-micro"
```

#### For PSC-Enabled Private Cluster:

```bash
# Copy the PSC example configuration
cp configuration/tfvars/terraform.tfvars.psc.example configuration/tfvars/terraform.tfvars
```

Edit `configuration/tfvars/terraform.tfvars`:

```hcl
gcp_project = "your-gcp-project-id"
clustername = "osd-psc-cluster"
vpc_routing_mode = "REGIONAL"
master_cidr_block = "10.0.0.0/19"      # 10.0.0.0 - 10.0.31.255
worker_cidr_block = "10.0.32.0/19"     # 10.0.32.0 - 10.0.63.255
psc_subnet_cidr_block = "10.0.64.0/29" # Must be within Machine CIDR (10.0.0.0/17)
bastion_cidr_block = "10.10.0.0/24"
gcp_region = "us-west1"
gcp_zone = "us-west1-a"
osd_gcp_psc = true
osd_gcp_private = true
enable_osd_gcp_bastion = true
gcp_authentication_type = "workload_identity_federation"
enable_psc_endpoints = [
  "storage.googleapis.com",
  "container.googleapis.com",
  "compute.googleapis.com",
  "logging.googleapis.com",
  "monitoring.googleapis.com"
]
```

**Important**: For PSC, ensure:
- PSC subnet CIDR is within Machine CIDR range (master + worker combined)
- PSC subnet is /29 or larger
- Cluster name matches what you'll use in OCM

#### For Multi-AZ Deployment:

Multi-AZ deployment distributes your cluster across multiple availability zones for high availability. In GCP, subnets are regional (automatically span all zones), but you need to specify which zones to use when creating the cluster.

**Option 1: Using Terraform with Multi-AZ Support (Recommended)**

The Terraform code now supports multi-AZ deployment. Simply add this to your `terraform.tfvars`:

```hcl
gcp_project = "your-gcp-project-id"
clustername = "your-cluster-name"
vpc_routing_mode = "REGIONAL"
master_cidr_block = "10.0.0.0/17"
worker_cidr_block = "10.0.128.0/17"
gcp_region = "us-west1"
gcp_zone = "us-west1-a"  # Used for bastion only
gcp_authentication_type = "workload_identity_federation"

# Multi-AZ configuration
# Specify the availability zones you want to use (typically 3 zones)
# Format: us-west1-a,us-west1-b,us-west1-c (comma-separated, no spaces)
gcp_availability_zones = "us-west1-a,us-west1-b,us-west1-c"
```

The Terraform template will automatically use these zones when creating the cluster. The cluster will be configured with:
- 3 control plane nodes (1 per zone, automatically distributed)
- 9 worker nodes minimum (3 per zone, automatically set)

**Note**: If you need more than 9 worker nodes, you can modify the `templates/clusterinstall.tftpl` file to change the `--compute-nodes` value. Ensure it's a multiple of 3 (e.g., 12, 15, 18).

**Option 2: Manual Multi-AZ Cluster Creation**

After deploying infrastructure with Terraform, create the cluster manually with OCM:

```bash
# Deploy infrastructure only (no cluster)
export TF_VAR_only_deploy_infra_no_osd=true
make all

# Then create cluster manually with multi-AZ
ocm create cluster your-cluster-name \
  --provider gcp \
  --vpc-name your-cluster-name-vpc \
  --region us-west1 \
  --control-plane-subnet your-cluster-name-master-subnet \
  --compute-subnet your-cluster-name-worker-subnet \
  --availability-zones us-west1-a,us-west1-b,us-west1-c \
  --compute-nodes 9 \
  --wif-config your-cluster-name-wif \
  --ccs
```

**Multi-AZ Requirements:**
- **Minimum nodes**: Multi-AZ requires at least 9 worker nodes (3 per zone) for CCS clusters
- **Node count**: Must be a multiple of 3 (3, 6, 9, 12, etc.)
- **Control plane**: Automatically distributed across zones (3 masters)
- **Zone format**: Use comma-separated list without spaces (e.g., `us-west1-a,us-west1-b,us-west1-c`)

**Combining Multi-AZ with Private/PSC:**

You can combine multi-AZ with private clusters or PSC:

```hcl
# Multi-AZ + Private Cluster
osd_gcp_private = true
enable_osd_gcp_bastion = true
gcp_availability_zones = "us-west1-a,us-west1-b,us-west1-c"

# Multi-AZ + PSC
osd_gcp_psc = true
osd_gcp_private = true
enable_osd_gcp_bastion = true
gcp_availability_zones = "us-west1-a,us-west1-b,us-west1-c"
```

### Step 3: Set Required Environment Variables

```bash
# Required: Cluster name (must match terraform.tfvars)
export TF_VAR_clustername=your-cluster-name

# Required for Service Account auth:
# export TF_VAR_gcp_sa_file_loc=~/.gcp/osd-ccs-admin.json

# Required for WIF auth:
# export TF_VAR_gcp_authentication_type=workload_identity_federation

# Optional: Custom SSH key location
# export TF_VAR_bastion_key_loc=~/.ssh/id_rsa.pub
```

### Step 4: Configure Backend (Optional)

The default backend uses local state. To use remote state, edit `configuration/backend/lab.conf`:

```hcl
# For GCS backend:
bucket = "your-terraform-state-bucket"
prefix = "osd/terraform/state"

# For local backend (default):
path = "state/terraform.lab.tfstate"
```

---

## Deployment

### Method 1: Using Makefile (Recommended)

The Makefile automates the entire deployment process:

```bash
# Deploy everything (infrastructure + cluster)
make all
```

This will:
1. Initialize Terraform
2. Plan infrastructure changes
3. Apply infrastructure (VPC, subnets, NAT, firewall rules)
4. Create Workload Identity Federation config (if using WIF)
5. Create OSD cluster via OCM CLI
6. Monitor cluster installation (30-45 minutes)

### Method 2: Manual Terraform Commands

If you prefer manual control:

```bash
# Set environment variables
export ENVIRONMENT="lab"
export TF_BACKEND_CONF="configuration/backend"
export TF_VARIABLES="configuration/tfvars"
export TF_VAR_clustername=your-cluster-name

# Initialize Terraform
terraform init -backend-config="$TF_BACKEND_CONF/$ENVIRONMENT.conf"

# Review changes
terraform plan -var-file="$TF_VARIABLES/terraform.tfvars" -out "output/tf.$ENVIRONMENT.plan"

# Apply changes
terraform apply output/tf.$ENVIRONMENT.plan
```

### What Gets Deployed

1. **VPC Network**: Custom VPC for the cluster
2. **Subnets**:
   - Master/Control Plane subnet
   - Worker/Compute subnet
   - PSC subnet (if PSC enabled)
   - Bastion subnet (if private cluster)
3. **NAT Gateways**: For outbound internet access
4. **Router**: Cloud Router for NAT
5. **Firewall Rules**: Required firewall rules for cluster communication
6. **Bastion Host** (if private cluster): Jump host for cluster access
7. **Workload Identity Federation** (if WIF auth): WIF configuration
8. **OSD Cluster**: OpenShift Dedicated cluster via OCM

### Monitoring Deployment

The deployment script monitors cluster installation progress:
- **Typical duration**: 30-45 minutes
- **Status updates**: Every 2 minutes
- **Final state**: "ready" when complete

You can also monitor via:
```bash
# Check cluster status
ocm list clusters

# Get detailed cluster info
ocm get /api/clusters_mgmt/v1/clusters/<cluster-id>
```

---

## Post-Deployment

### For Public Clusters

1. **Get Cluster Credentials**:
   ```bash
   ocm cluster login your-cluster-name
   ```

2. **Access Web Console**:
   - Get console URL: `ocm describe cluster your-cluster-name`
   - Open in browser and login

3. **Verify Deployment**:
   ```bash
   oc whoami
   oc get nodes
   oc get pods -A
   ```

4. **Verify Multi-AZ Distribution** (if using multi-AZ):
   ```bash
   # Check node distribution across zones
   oc get nodes -o wide
   
   # Verify nodes are in different zones
   oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | sort -k2
   
   # Expected output should show nodes distributed across zones:
   # node-1    us-west1-a
   # node-2    us-west1-a
   # node-3    us-west1-a
   # node-4    us-west1-b
   # node-5    us-west1-b
   # node-6    us-west1-b
   # node-7    us-west1-c
   # node-8    us-west1-c
   # node-9    us-west1-c
   
   # Verify control plane nodes are distributed
   oc get nodes -l node-role.kubernetes.io/master -o wide
   ```

### For Private Clusters

1. **SSH to Bastion Host**:
   ```bash
   gcloud compute ssh ${CLUSTERNAME}-bastion-vm \
     --zone=${GCP_ZONE} \
     --project=${GCP_PROJECT}
   ```

2. **Configure Identity Provider** (from your local machine):
   - Go to https://console.redhat.com
   - Find your cluster
   - Navigate to "Access control" → "Identity providers"
   - Add an IdP (recommended: htpasswd)
   - Grant admin access to users

3. **Access Cluster from Bastion**:
   ```bash
   # From bastion, login to OCM
   ocm login --use-device-code
   
   # Login to cluster
   oc login https://api.${CLUSTERNAME}.<domain>.openshiftapps.com:6443 \
     --username=<your-username> \
     --password=<your-password> \
     --insecure-skip-tls-verify=true
   ```

### For PSC-Enabled Private Clusters

1. **SSH to Bastion**:
   ```bash
   gcloud compute ssh ${CLUSTERNAME}-bastion-vm \
     --zone=${GCP_ZONE} \
     --project=${GCP_PROJECT}
   ```

2. **Install OCM CLI on Bastion** (if needed):
   ```bash
   wget https://github.com/openshift-online/ocm-cli/releases/download/v0.1.73/ocm-linux-amd64
   sudo mv ocm-linux-amd64 /usr/bin/ocm
   sudo chmod +x /usr/bin/ocm
   ```

3. **Test API Connectivity**:
   ```bash
   # Find API endpoint
   nslookup api.${CLUSTERNAME}.<domain>.openshiftapps.com
   
   # Test health endpoint
   curl -k https://api.${CLUSTERNAME}.<domain>.openshiftapps.com:6443/healthz
   ```

4. **Configure Identity Provider** (from local browser):
   - Same as private cluster steps above

5. **Access Cluster**:
   ```bash
   # From bastion
   ocm login --use-device-code
   oc login https://api.${CLUSTERNAME}.<domain>.openshiftapps.com:6443 \
     --username=<your-username> \
     --password=<your-password> \
     --insecure-skip-tls-verify=true
   ```

6. **Verify Deployment**:
   ```bash
   oc whoami
   oc get nodes
   oc get pods -A | grep -E "(psc|apiserver)"
   ```

---

## Cleanup

### Destroy Everything

```bash
# Set cluster name
export TF_VAR_clustername=your-cluster-name

# Destroy infrastructure and cluster
make destroy
```

This will:
1. Delete the OSD cluster via OCM
2. Destroy all Terraform-managed infrastructure
3. Clean up local state files

### Manual Cleanup

```bash
# Delete cluster via OCM
ocm delete cluster your-cluster-name

# Destroy infrastructure
terraform destroy -var-file="configuration/tfvars/terraform.tfvars" -auto-approve

# Clean up local files
rm -rf .terraform
rm -rf output/tf.*.plan
rm -rf state/terraform*
rm -rf .terraform.lock.hcl
```

---

## Troubleshooting

### Common Issues

#### 1. OCM CLI Not Found
```bash
# Verify installation
which ocm
ocm version

# Reinstall if needed
wget https://github.com/openshift-online/ocm-cli/releases/download/v0.1.73/ocm-linux-amd64
chmod +x ocm-linux-amd64
sudo mv ocm-linux-amd64 /usr/local/bin/ocm
```

#### 2. Authentication Errors
- **WIF**: Verify WIF configuration exists: `gcloud iam workload-identity-pools list`
- **Service Account**: Verify SA key file exists and is valid: `cat $TF_VAR_gcp_sa_file_loc | jq .`

#### 3. Cluster Creation Fails
- Check OCM logs: `ocm get /api/clusters_mgmt/v1/clusters/<cluster-id>`
- Verify GCP APIs are enabled
- Check firewall rules and network configuration
- Ensure CIDR ranges don't overlap

#### 4. Can't Access Private Cluster API
- Verify firewall rules are in correct VPC
- Check bastion can reach master IPs
- Ensure identity provider is configured
- Verify cluster name matches in all places

#### 5. PSC-Specific Issues
- **CIDR conflicts**: Ensure PSC subnet is within Machine CIDR
- **API timeout**: Check firewall rules use IP ranges (not tags)
- **DNS resolution**: Verify PSC DNS zones are configured

#### 6. Multi-AZ Deployment Issues
- **Insufficient nodes**: Multi-AZ requires minimum 9 worker nodes (3 per zone)
- **Node count not multiple of 3**: Ensure worker node count is divisible by 3
- **Zone availability**: Verify all specified zones are available in your GCP project
- **Zone format**: Use comma-separated format without spaces: `us-west1-a,us-west1-b,us-west1-c`
- **Verify zone distribution**: After deployment, check node distribution with `oc get nodes -o wide`
- **Control plane distribution**: Masters should be in different zones (automatically handled)

### Getting Help

- **Red Hat Documentation**: https://docs.openshift.com/dedicated/
- **OCM CLI Issues**: https://github.com/openshift-online/ocm-cli
- **Terraform GCP Provider**: https://registry.terraform.io/providers/hashicorp/google/latest/docs

---

## Additional Resources

- [OpenShift Dedicated Documentation](https://docs.openshift.com/dedicated/)
- [GCP CCS Customer Procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html)
- [Workload Identity Federation Guide](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-cluster-with-workload-identity-federation.html)
- [Private Service Connect Guide](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-psc-enabled-private-cluster.html)

---

## Summary Checklist

Before deploying, ensure you have:

- [ ] OCM CLI installed (v0.1.73+)
- [ ] Terraform installed (v0.14+)
- [ ] gcloud CLI installed and authenticated
- [ ] jq installed
- [ ] Red Hat account with OSD subscription
- [ ] OCM CLI logged in (`ocm login`)
- [ ] GCP project created and APIs enabled
- [ ] Authentication method configured (WIF or SA)
- [ ] `terraform.tfvars` configured
- [ ] Environment variables set (`TF_VAR_clustername`, etc.)
- [ ] SSH key available (for bastion, if private cluster)
- [ ] Availability zones specified (for multi-AZ deployment)

Then run: `make all`

---

## Multi-AZ Deployment Quick Reference

For a quick multi-AZ deployment:

```bash
# 1. Configure terraform.tfvars
gcp_availability_zones = "us-west1-a,us-west1-b,us-west1-c"

# 2. Set cluster name
export TF_VAR_clustername=your-cluster-name

# 3. Deploy
make all

# 4. Verify zone distribution
oc get nodes -o wide
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | sort -k2
```

**Key Points:**
- GCP subnets are regional (automatically span all zones)
- Multi-AZ requires minimum 9 worker nodes (3 per zone)
- Control plane automatically distributed (3 masters, 1 per zone)
- Can combine with private cluster or PSC
- Node count must be multiple of 3
- Format: comma-separated zones without spaces

Good luck with your deployment! 🚀
