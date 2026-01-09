#!/bin/bash
#
# OSD Private VPC Infrastructure Setup Script (Hub-Spoke Architecture)
# 
# This script creates:
# 1. Landing Zone VPC (Hub) with Cloud NAT and Squid Proxy for egress
# 2. OSD VPC (Spoke) with required subnets (completely private, no NAT)
# 3. VPC Peering between Landing Zone and OSD VPCs
# 4. Squid Proxy VM in Hub VPC for container image pulls from spoke
#
# Architecture:
#   ┌─────────────────────────┐         ┌─────────────────────────┐
#   │  Landing Zone VPC (Hub) │         │    OSD VPC (Spoke)      │
#   │  10.100.0.0/24          │         │    10.0.0.0/16          │
#   │                         │         │                         │
#   │  ┌─────────────────┐    │  Peer   │  ┌─────────┐ ┌────────┐│
#   │  │ Squid Proxy/    │◄───┼─────────┼─►│ Masters │ │Workers ││
#   │  │ Bastion         │    │         │  │ API:6443│ │ :443   ││
#   │  │ (10.100.0.10)   │    │         │  └─────────┘ └────────┘│
#   │  └────────┬────────┘    │         │                         │
#   │           │             │         │  ┌──────────────────┐  │
#   │  ┌────────▼────────┐    │         │  │ PSC (Google APIs)│  │
#   │  │ Cloud NAT       │    │         │  └──────────────────┘  │
#   │  └────────┬────────┘    │         │                         │
#   │           ▼             │         │  Firewall allows:       │
#   │       Internet          │         │  - tcp:6443 (API)       │
#   └─────────────────────────┘         │  - tcp:443,80 (Ingress) │
#                                       │  - tcp:22, icmp         │
#                                       │  from 10.100.0.0/24     │
#                                       └─────────────────────────┘
#
# The OSD VPC can then be used with Terraform to deploy OpenShift Dedicated
#
# Usage:
#   ./setup-vpc-infrastructure.sh [options]
#
# Options:
#   -p, --project         GCP Project ID (required)
#   -r, --region          GCP Region (default: us-central1)
#   -c, --cluster-name    Cluster name prefix for resources (default: osd-cluster)
#   -d, --delete          Delete all resources instead of creating
#   --configure-dns       Configure DNS peering (run after cluster is deployed)
#   -h, --help            Show this help message
#
# Example:
#   ./setup-vpc-infrastructure.sh -p my-project -r asia-south1 -c sgaikwad
#

set -e

# Default values
PROJECT_ID=""
REGION="us-central1"
CLUSTER_NAME="osd-cluster"
DELETE_MODE=false
CONFIGURE_DNS_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    head -48 "$0" | tail -43
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -d|--delete)
            DELETE_MODE=true
            shift
            ;;
        --configure-dns)
            CONFIGURE_DNS_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate required parameters
if [ -z "$PROJECT_ID" ]; then
    log_error "Project ID is required. Use -p or --project to specify."
    show_help
fi

# Resource naming
LZ_VPC_NAME="landing-zone-vpc"
LZ_SUBNET_NAME="landing-zone-subnet"
LZ_ROUTER_NAME="landing-zone-router"
LZ_NAT_NAME="landing-zone-nat"
LZ_PROXY_NAME="landing-zone-proxy"
LZ_PROXY_FW_NAME="landing-zone-proxy-allow"

OSD_VPC_NAME="${CLUSTER_NAME}-vpc"
OSD_MASTER_SUBNET_NAME="${CLUSTER_NAME}-master-subnet"
OSD_WORKER_SUBNET_NAME="${CLUSTER_NAME}-worker-subnet"
OSD_PSC_SUBNET_NAME="${CLUSTER_NAME}-psc-subnet"
OSD_BASTION_SUBNET_NAME="${CLUSTER_NAME}-bastion-subnet"
OSD_ROUTER_NAME="${CLUSTER_NAME}-router"
OSD_FW_FROM_LZ_NAME="${CLUSTER_NAME}-allow-from-landing-zone"

PEERING_OSD_TO_LZ="osd-to-landing-zone"
PEERING_LZ_TO_OSD="landing-zone-to-osd"

# CIDR ranges
LZ_SUBNET_CIDR="10.100.0.0/24"
LZ_PROXY_IP="10.100.0.10"  # Static internal IP for proxy
OSD_MASTER_CIDR="10.0.0.0/19"
OSD_WORKER_CIDR="10.0.32.0/19"
OSD_PSC_CIDR="10.0.64.0/29"
OSD_BASTION_CIDR="10.10.0.0/24"

# Proxy settings
PROXY_MACHINE_TYPE="e2-medium"
PROXY_PORT="3128"

# Allowed domains for proxy (from Red Hat OSD GCP PSC firewall prerequisites)
# Reference: https://docs.redhat.com/en/documentation/openshift_dedicated/4/html-single/planning_your_environment/index#osd-gcp-psc-firewall-prerequisites_gcp-ccs
ALLOWED_DOMAINS=(
    # Red Hat Core Services
    ".redhat.com"
    ".redhat.io"
    ".quay.io"
    ".openshift.com"
    # Specific Red Hat endpoints
    "registry.redhat.io"
    "quay.io"
    "cdn.quay.io"
    "cdn01.quay.io"
    "cdn02.quay.io"
    "cdn03.quay.io"
    "sso.redhat.com"
    "access.redhat.com"
    "cert-api.access.redhat.com"
    "api.access.redhat.com"
    "infogw.api.openshift.com"
    "console.redhat.com"
    "cloud.redhat.com"
    "observatorium.api.openshift.com"
    "observatorium-mst.api.openshift.com"
    "mirror.openshift.com"
    "api.openshift.com"
    # Google Cloud Services
    ".googleapis.com"
    ".gcr.io"
    ".pkg.dev"
    "storage.googleapis.com"
    "console.cloud.google.com"
    "oauth2.googleapis.com"
    "accounts.google.com"
    # Container Registries
    ".docker.io"
    ".docker.com"
    "registry-1.docker.io"
    "auth.docker.io"
    "production.cloudflare.docker.com"
    # GitHub (for operators and tools)
    ".github.com"
    ".githubusercontent.com"
    "github.com"
    "raw.githubusercontent.com"
    "objects.githubusercontent.com"
    # Cloud CDNs and Object Storage (for image layers)
    ".cloudfront.net"
    ".amazonaws.com"
    ".s3.amazonaws.com"
    ".azure.com"
    ".azurecr.io"
    ".windows.net"
    # OpenShift Telemetry and Updates
    "registry.connect.redhat.com"
    "registry.access.redhat.com"
    # Operator Hub
    "catalog.redhat.com"
)

# Function to check if a resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local extra_args=$3
    
    case $resource_type in
        "network")
            gcloud compute networks describe "$resource_name" --project="$PROJECT_ID" &>/dev/null
            ;;
        "subnet")
            gcloud compute networks subnets describe "$resource_name" --project="$PROJECT_ID" --region="$REGION" &>/dev/null
            ;;
        "router")
            gcloud compute routers describe "$resource_name" --project="$PROJECT_ID" --region="$REGION" &>/dev/null
            ;;
        "nat")
            gcloud compute routers nats describe "$resource_name" --router="$extra_args" --project="$PROJECT_ID" --region="$REGION" &>/dev/null
            ;;
        "peering")
            gcloud compute networks peerings list --network="$extra_args" --project="$PROJECT_ID" --format="value(name)" | grep -q "^${resource_name}$"
            ;;
        "instance")
            gcloud compute instances describe "$resource_name" --project="$PROJECT_ID" --zone="$extra_args" &>/dev/null
            ;;
        "firewall")
            gcloud compute firewall-rules describe "$resource_name" --project="$PROJECT_ID" &>/dev/null
            ;;
        "address")
            gcloud compute addresses describe "$resource_name" --project="$PROJECT_ID" --region="$REGION" &>/dev/null
            ;;
    esac
}

# Delete function
delete_infrastructure() {
    log_info "Starting infrastructure deletion..."
    
    local ZONE="${REGION}-a"
    
    # Delete VPC Peerings
    log_info "Deleting VPC peerings..."
    if resource_exists "peering" "$PEERING_OSD_TO_LZ" "$OSD_VPC_NAME"; then
        gcloud compute networks peerings delete "$PEERING_OSD_TO_LZ" --network="$OSD_VPC_NAME" --project="$PROJECT_ID" --quiet || true
        log_success "Deleted peering: $PEERING_OSD_TO_LZ"
    fi
    
    if resource_exists "peering" "$PEERING_LZ_TO_OSD" "$LZ_VPC_NAME"; then
        gcloud compute networks peerings delete "$PEERING_LZ_TO_OSD" --network="$LZ_VPC_NAME" --project="$PROJECT_ID" --quiet || true
        log_success "Deleted peering: $PEERING_LZ_TO_OSD"
    fi
    
    # Delete OSD VPC resources
    log_info "Deleting OSD VPC resources..."
    
    # Delete firewall rule for landing zone access
    if resource_exists "firewall" "$OSD_FW_FROM_LZ_NAME"; then
        gcloud compute firewall-rules delete "$OSD_FW_FROM_LZ_NAME" --project="$PROJECT_ID" --quiet || true
        log_success "Deleted firewall: $OSD_FW_FROM_LZ_NAME"
    fi
    
    if resource_exists "router" "$OSD_ROUTER_NAME"; then
        gcloud compute routers delete "$OSD_ROUTER_NAME" --project="$PROJECT_ID" --region="$REGION" --quiet || true
        log_success "Deleted router: $OSD_ROUTER_NAME"
    fi
    
    for subnet in "$OSD_BASTION_SUBNET_NAME" "$OSD_PSC_SUBNET_NAME" "$OSD_WORKER_SUBNET_NAME" "$OSD_MASTER_SUBNET_NAME"; do
        if resource_exists "subnet" "$subnet"; then
            gcloud compute networks subnets delete "$subnet" --project="$PROJECT_ID" --region="$REGION" --quiet || true
            log_success "Deleted subnet: $subnet"
        fi
    done
    
    if resource_exists "network" "$OSD_VPC_NAME"; then
        gcloud compute networks delete "$OSD_VPC_NAME" --project="$PROJECT_ID" --quiet || true
        log_success "Deleted VPC: $OSD_VPC_NAME"
    fi
    
    # Delete Squid Proxy resources
    log_info "Deleting Squid Proxy resources..."
    
    if resource_exists "instance" "$LZ_PROXY_NAME" "$ZONE"; then
        gcloud compute instances delete "$LZ_PROXY_NAME" --project="$PROJECT_ID" --zone="$ZONE" --quiet || true
        log_success "Deleted proxy VM: $LZ_PROXY_NAME"
    fi
    
    if resource_exists "firewall" "$LZ_PROXY_FW_NAME"; then
        gcloud compute firewall-rules delete "$LZ_PROXY_FW_NAME" --project="$PROJECT_ID" --quiet || true
        log_success "Deleted firewall: $LZ_PROXY_FW_NAME"
    fi
    
    if resource_exists "firewall" "${LZ_PROXY_FW_NAME}-health"; then
        gcloud compute firewall-rules delete "${LZ_PROXY_FW_NAME}-health" --project="$PROJECT_ID" --quiet || true
        log_success "Deleted firewall: ${LZ_PROXY_FW_NAME}-health"
    fi
    
    if resource_exists "address" "${LZ_PROXY_NAME}-ip"; then
        gcloud compute addresses delete "${LZ_PROXY_NAME}-ip" --project="$PROJECT_ID" --region="$REGION" --quiet || true
        log_success "Deleted static IP: ${LZ_PROXY_NAME}-ip"
    fi
    
    # Delete Landing Zone resources
    log_info "Deleting Landing Zone resources..."
    
    if resource_exists "nat" "$LZ_NAT_NAME" "$LZ_ROUTER_NAME"; then
        gcloud compute routers nats delete "$LZ_NAT_NAME" --router="$LZ_ROUTER_NAME" --project="$PROJECT_ID" --region="$REGION" --quiet || true
        log_success "Deleted NAT: $LZ_NAT_NAME"
    fi
    
    if resource_exists "router" "$LZ_ROUTER_NAME"; then
        gcloud compute routers delete "$LZ_ROUTER_NAME" --project="$PROJECT_ID" --region="$REGION" --quiet || true
        log_success "Deleted router: $LZ_ROUTER_NAME"
    fi
    
    if resource_exists "subnet" "$LZ_SUBNET_NAME"; then
        gcloud compute networks subnets delete "$LZ_SUBNET_NAME" --project="$PROJECT_ID" --region="$REGION" --quiet || true
        log_success "Deleted subnet: $LZ_SUBNET_NAME"
    fi
    
    if resource_exists "network" "$LZ_VPC_NAME"; then
        gcloud compute networks delete "$LZ_VPC_NAME" --project="$PROJECT_ID" --quiet || true
        log_success "Deleted VPC: $LZ_VPC_NAME"
    fi
    
    log_success "Infrastructure deletion completed!"
}

# Create Landing Zone VPC
create_landing_zone_vpc() {
    log_info "Creating Landing Zone VPC infrastructure..."
    
    # Create VPC
    if resource_exists "network" "$LZ_VPC_NAME"; then
        log_warning "VPC $LZ_VPC_NAME already exists, skipping..."
    else
        log_info "Creating VPC: $LZ_VPC_NAME"
        gcloud compute networks create "$LZ_VPC_NAME" \
            --project="$PROJECT_ID" \
            --subnet-mode=custom \
            --bgp-routing-mode=regional
        log_success "Created VPC: $LZ_VPC_NAME"
    fi
    
    # Create Subnet
    if resource_exists "subnet" "$LZ_SUBNET_NAME"; then
        log_warning "Subnet $LZ_SUBNET_NAME already exists, skipping..."
    else
        log_info "Creating subnet: $LZ_SUBNET_NAME ($LZ_SUBNET_CIDR)"
        gcloud compute networks subnets create "$LZ_SUBNET_NAME" \
            --project="$PROJECT_ID" \
            --network="$LZ_VPC_NAME" \
            --region="$REGION" \
            --range="$LZ_SUBNET_CIDR"
        log_success "Created subnet: $LZ_SUBNET_NAME"
    fi
    
    # Create Cloud Router
    if resource_exists "router" "$LZ_ROUTER_NAME"; then
        log_warning "Router $LZ_ROUTER_NAME already exists, skipping..."
    else
        log_info "Creating Cloud Router: $LZ_ROUTER_NAME"
        gcloud compute routers create "$LZ_ROUTER_NAME" \
            --project="$PROJECT_ID" \
            --network="$LZ_VPC_NAME" \
            --region="$REGION"
        log_success "Created router: $LZ_ROUTER_NAME"
    fi
    
    # Create Cloud NAT
    if resource_exists "nat" "$LZ_NAT_NAME" "$LZ_ROUTER_NAME"; then
        log_warning "NAT $LZ_NAT_NAME already exists, skipping..."
    else
        log_info "Creating Cloud NAT: $LZ_NAT_NAME"
        gcloud compute routers nats create "$LZ_NAT_NAME" \
            --project="$PROJECT_ID" \
            --router="$LZ_ROUTER_NAME" \
            --region="$REGION" \
            --nat-all-subnet-ip-ranges \
            --auto-allocate-nat-external-ips
        log_success "Created NAT: $LZ_NAT_NAME"
    fi
    
    log_success "Landing Zone VPC infrastructure created!"
}

# Generate Squid proxy startup script
generate_squid_startup_script() {
    cat << 'SQUID_SCRIPT'
#!/bin/bash
set -e

# Install Squid
apt-get update
apt-get install -y squid

# Backup original config
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# Create Squid configuration - simplified to allow all traffic from private networks
# This avoids issues with dynamic subdomains like pull.q1w2.quay.rhcloud.com
cat > /etc/squid/squid.conf << 'EOF'
# Squid Proxy Configuration for OSD
# Allows all traffic from private networks (10.x, 172.16.x, 192.168.x)
# This is required because OSD uses dynamic subdomains that cannot be predicted

# Basic settings
http_port 3128
visible_hostname squid-proxy

# Access control lists - private network ranges
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16

# SSL ports
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 8443
acl CONNECT method CONNECT

# Deny requests to non-safe ports
http_access deny !Safe_ports

# Deny CONNECT to non-SSL ports
http_access deny CONNECT !SSL_ports

# Allow localhost manager
http_access allow localhost manager
http_access deny manager

# Allow ALL traffic from private networks
# This is necessary because OSD uses dynamic domains like:
# - pull.q1w2.quay.rhcloud.com
# - api.xxx.p1.openshiftapps.com
http_access allow localnet

# Allow localhost
http_access allow localhost

# Deny all other access (from internet)
http_access deny all

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
EOF

# Initialize cache directory
squid -z 2>/dev/null || true

# Enable and start Squid
systemctl enable squid
systemctl restart squid

echo "Squid proxy installation complete"
SQUID_SCRIPT
}

# Create Squid Proxy in Landing Zone
create_squid_proxy() {
    log_info "Creating Squid Proxy in Landing Zone VPC..."
    
    local ZONE="${REGION}-a"
    
    # Reserve static internal IP for proxy
    if resource_exists "address" "${LZ_PROXY_NAME}-ip"; then
        log_warning "Static IP ${LZ_PROXY_NAME}-ip already exists, skipping..."
    else
        log_info "Reserving static internal IP: ${LZ_PROXY_NAME}-ip ($LZ_PROXY_IP)"
        gcloud compute addresses create "${LZ_PROXY_NAME}-ip" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --subnet="$LZ_SUBNET_NAME" \
            --addresses="$LZ_PROXY_IP"
        log_success "Reserved static IP: ${LZ_PROXY_NAME}-ip"
    fi
    
    # Create firewall rule to allow proxy traffic from OSD VPC
    if resource_exists "firewall" "$LZ_PROXY_FW_NAME"; then
        log_warning "Firewall rule $LZ_PROXY_FW_NAME already exists, skipping..."
    else
        log_info "Creating firewall rule: $LZ_PROXY_FW_NAME"
        gcloud compute firewall-rules create "$LZ_PROXY_FW_NAME" \
            --project="$PROJECT_ID" \
            --network="$LZ_VPC_NAME" \
            --direction=INGRESS \
            --priority=1000 \
            --action=ALLOW \
            --rules=tcp:${PROXY_PORT} \
            --source-ranges="${OSD_MASTER_CIDR},${OSD_WORKER_CIDR},${OSD_BASTION_CIDR}" \
            --target-tags="squid-proxy" \
            --description="Allow proxy traffic from OSD VPC subnets"
        log_success "Created firewall rule: $LZ_PROXY_FW_NAME"
    fi
    
    # Create firewall rule to allow health checks
    if resource_exists "firewall" "${LZ_PROXY_FW_NAME}-health"; then
        log_warning "Firewall rule ${LZ_PROXY_FW_NAME}-health already exists, skipping..."
    else
        log_info "Creating firewall rule: ${LZ_PROXY_FW_NAME}-health"
        gcloud compute firewall-rules create "${LZ_PROXY_FW_NAME}-health" \
            --project="$PROJECT_ID" \
            --network="$LZ_VPC_NAME" \
            --direction=INGRESS \
            --priority=1000 \
            --action=ALLOW \
            --rules=tcp:22 \
            --source-ranges="35.235.240.0/20" \
            --target-tags="squid-proxy" \
            --description="Allow IAP SSH access to proxy"
        log_success "Created firewall rule: ${LZ_PROXY_FW_NAME}-health"
    fi
    
    # Create Squid Proxy VM
    if resource_exists "instance" "$LZ_PROXY_NAME" "$ZONE"; then
        log_warning "Proxy VM $LZ_PROXY_NAME already exists, skipping..."
    else
        log_info "Creating Squid Proxy VM: $LZ_PROXY_NAME"
        
        # Generate startup script to a temporary file
        local STARTUP_SCRIPT_FILE=$(mktemp)
        generate_squid_startup_script > "$STARTUP_SCRIPT_FILE"
        
        gcloud compute instances create "$LZ_PROXY_NAME" \
            --project="$PROJECT_ID" \
            --zone="$ZONE" \
            --machine-type="$PROXY_MACHINE_TYPE" \
            --network-interface="network=${LZ_VPC_NAME},subnet=${LZ_SUBNET_NAME},private-network-ip=${LZ_PROXY_IP},no-address" \
            --tags="squid-proxy" \
            --image-family="debian-12" \
            --image-project="debian-cloud" \
            --boot-disk-size="50GB" \
            --boot-disk-type="pd-standard" \
            --metadata-from-file="startup-script=${STARTUP_SCRIPT_FILE}" \
            --shielded-secure-boot \
            --shielded-vtpm \
            --shielded-integrity-monitoring \
            --service-account="default" \
            --scopes="https://www.googleapis.com/auth/cloud-platform"
        
        # Clean up temp file
        rm -f "$STARTUP_SCRIPT_FILE"
        
        log_success "Created Squid Proxy VM: $LZ_PROXY_NAME"
        log_info "Proxy will be available at: ${LZ_PROXY_IP}:${PROXY_PORT}"
        log_info "Note: Allow 2-3 minutes for Squid to install and start"
    fi
    
    log_success "Squid Proxy setup complete!"
}

# Create OSD VPC
create_osd_vpc() {
    log_info "Creating OSD VPC infrastructure..."
    
    # Create VPC
    if resource_exists "network" "$OSD_VPC_NAME"; then
        log_warning "VPC $OSD_VPC_NAME already exists, skipping..."
    else
        log_info "Creating VPC: $OSD_VPC_NAME"
        gcloud compute networks create "$OSD_VPC_NAME" \
            --project="$PROJECT_ID" \
            --subnet-mode=custom \
            --bgp-routing-mode=regional
        log_success "Created VPC: $OSD_VPC_NAME"
    fi
    
    # Create Master Subnet
    if resource_exists "subnet" "$OSD_MASTER_SUBNET_NAME"; then
        log_warning "Subnet $OSD_MASTER_SUBNET_NAME already exists, skipping..."
    else
        log_info "Creating master subnet: $OSD_MASTER_SUBNET_NAME ($OSD_MASTER_CIDR)"
        gcloud compute networks subnets create "$OSD_MASTER_SUBNET_NAME" \
            --project="$PROJECT_ID" \
            --network="$OSD_VPC_NAME" \
            --region="$REGION" \
            --range="$OSD_MASTER_CIDR" \
            --enable-private-ip-google-access
        log_success "Created subnet: $OSD_MASTER_SUBNET_NAME"
    fi
    
    # Create Worker Subnet
    if resource_exists "subnet" "$OSD_WORKER_SUBNET_NAME"; then
        log_warning "Subnet $OSD_WORKER_SUBNET_NAME already exists, skipping..."
    else
        log_info "Creating worker subnet: $OSD_WORKER_SUBNET_NAME ($OSD_WORKER_CIDR)"
        gcloud compute networks subnets create "$OSD_WORKER_SUBNET_NAME" \
            --project="$PROJECT_ID" \
            --network="$OSD_VPC_NAME" \
            --region="$REGION" \
            --range="$OSD_WORKER_CIDR" \
            --enable-private-ip-google-access
        log_success "Created subnet: $OSD_WORKER_SUBNET_NAME"
    fi
    
    # Create PSC Subnet (for Private Service Connect)
    if resource_exists "subnet" "$OSD_PSC_SUBNET_NAME"; then
        log_warning "Subnet $OSD_PSC_SUBNET_NAME already exists, skipping..."
    else
        log_info "Creating PSC subnet: $OSD_PSC_SUBNET_NAME ($OSD_PSC_CIDR)"
        gcloud compute networks subnets create "$OSD_PSC_SUBNET_NAME" \
            --project="$PROJECT_ID" \
            --network="$OSD_VPC_NAME" \
            --region="$REGION" \
            --range="$OSD_PSC_CIDR" \
            --purpose=PRIVATE_SERVICE_CONNECT
        log_success "Created subnet: $OSD_PSC_SUBNET_NAME"
    fi
    
    # Create Bastion Subnet
    if resource_exists "subnet" "$OSD_BASTION_SUBNET_NAME"; then
        log_warning "Subnet $OSD_BASTION_SUBNET_NAME already exists, skipping..."
    else
        log_info "Creating bastion subnet: $OSD_BASTION_SUBNET_NAME ($OSD_BASTION_CIDR)"
        gcloud compute networks subnets create "$OSD_BASTION_SUBNET_NAME" \
            --project="$PROJECT_ID" \
            --network="$OSD_VPC_NAME" \
            --region="$REGION" \
            --range="$OSD_BASTION_CIDR" \
            --enable-private-ip-google-access
        log_success "Created subnet: $OSD_BASTION_SUBNET_NAME"
    fi
    
    # Create Cloud Router (required for OSD even without NAT)
    if resource_exists "router" "$OSD_ROUTER_NAME"; then
        log_warning "Router $OSD_ROUTER_NAME already exists, skipping..."
    else
        log_info "Creating Cloud Router: $OSD_ROUTER_NAME"
        gcloud compute routers create "$OSD_ROUTER_NAME" \
            --project="$PROJECT_ID" \
            --network="$OSD_VPC_NAME" \
            --region="$REGION"
        log_success "Created router: $OSD_ROUTER_NAME"
    fi
    
    # Create firewall rule to allow traffic from Landing Zone VPC
    # This enables bastion/proxy access to the OSD cluster API and ingress
    if resource_exists "firewall" "$OSD_FW_FROM_LZ_NAME"; then
        log_warning "Firewall rule $OSD_FW_FROM_LZ_NAME already exists, skipping..."
    else
        log_info "Creating firewall rule: $OSD_FW_FROM_LZ_NAME"
        gcloud compute firewall-rules create "$OSD_FW_FROM_LZ_NAME" \
            --project="$PROJECT_ID" \
            --network="$OSD_VPC_NAME" \
            --direction=INGRESS \
            --priority=1000 \
            --action=ALLOW \
            --rules=tcp:6443,tcp:443,tcp:80,tcp:22,icmp \
            --source-ranges="$LZ_SUBNET_CIDR" \
            --description="Allow API, ingress, SSH and ICMP from landing zone VPC (bastion/proxy access)"
        log_success "Created firewall rule: $OSD_FW_FROM_LZ_NAME"
    fi
    
    log_success "OSD VPC infrastructure created!"
}

# Create VPC Peering
create_vpc_peering() {
    log_info "Creating VPC peering between Landing Zone and OSD VPCs..."
    
    # Check if OSD VPC exists
    if ! resource_exists "network" "$OSD_VPC_NAME"; then
        log_error "OSD VPC $OSD_VPC_NAME does not exist. Cannot create peering."
        exit 1
    fi
    
    # Check if Landing Zone VPC exists
    if ! resource_exists "network" "$LZ_VPC_NAME"; then
        log_error "Landing Zone VPC $LZ_VPC_NAME does not exist. Cannot create peering."
        exit 1
    fi
    
    # Create peering from OSD to Landing Zone
    if resource_exists "peering" "$PEERING_OSD_TO_LZ" "$OSD_VPC_NAME"; then
        log_warning "Peering $PEERING_OSD_TO_LZ already exists, skipping..."
    else
        log_info "Creating peering: $PEERING_OSD_TO_LZ (OSD -> Landing Zone)"
        gcloud compute networks peerings create "$PEERING_OSD_TO_LZ" \
            --project="$PROJECT_ID" \
            --network="$OSD_VPC_NAME" \
            --peer-network="$LZ_VPC_NAME" \
            --export-custom-routes \
            --import-custom-routes
        log_success "Created peering: $PEERING_OSD_TO_LZ"
    fi
    
    # Create peering from Landing Zone to OSD
    if resource_exists "peering" "$PEERING_LZ_TO_OSD" "$LZ_VPC_NAME"; then
        log_warning "Peering $PEERING_LZ_TO_OSD already exists, skipping..."
    else
        log_info "Creating peering: $PEERING_LZ_TO_OSD (Landing Zone -> OSD)"
        gcloud compute networks peerings create "$PEERING_LZ_TO_OSD" \
            --project="$PROJECT_ID" \
            --network="$LZ_VPC_NAME" \
            --peer-network="$OSD_VPC_NAME" \
            --export-custom-routes \
            --import-custom-routes
        log_success "Created peering: $PEERING_LZ_TO_OSD"
    fi
    
    log_success "VPC peering created!"
}

# Print summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "         Infrastructure Summary"
    echo "=============================================="
    echo ""
    echo "Project:      $PROJECT_ID"
    echo "Region:       $REGION"
    echo "Cluster Name: $CLUSTER_NAME"
    echo ""
    echo "Landing Zone VPC (Hub):"
    echo "  VPC:        $LZ_VPC_NAME"
    echo "  Subnet:     $LZ_SUBNET_NAME ($LZ_SUBNET_CIDR)"
    echo "  Router:     $LZ_ROUTER_NAME"
    echo "  NAT:        $LZ_NAT_NAME"
    echo ""
    echo "Squid Proxy (Egress Gateway):"
    echo "  VM:         $LZ_PROXY_NAME"
    echo "  IP:         ${LZ_PROXY_IP}:${PROXY_PORT}"
    echo "  Machine:    $PROXY_MACHINE_TYPE"
    echo ""
    echo "OSD VPC (Spoke - Private, no NAT):"
    echo "  VPC:        $OSD_VPC_NAME"
    echo "  Master:     $OSD_MASTER_SUBNET_NAME ($OSD_MASTER_CIDR)"
    echo "  Worker:     $OSD_WORKER_SUBNET_NAME ($OSD_WORKER_CIDR)"
    echo "  PSC:        $OSD_PSC_SUBNET_NAME ($OSD_PSC_CIDR)"
    echo "  Bastion:    $OSD_BASTION_SUBNET_NAME ($OSD_BASTION_CIDR)"
    echo "  Router:     $OSD_ROUTER_NAME"
    echo "  Firewall:   $OSD_FW_FROM_LZ_NAME (allows access from landing zone)"
    echo ""
    echo "VPC Peering:"
    echo "  $PEERING_OSD_TO_LZ (OSD -> Landing Zone)"
    echo "  $PEERING_LZ_TO_OSD (Landing Zone -> OSD)"
    echo ""
    echo "=============================================="
    echo ""
    echo "PROXY CONFIGURATION FOR OSD CLUSTER:"
    echo "=============================================="
    echo ""
    echo "After cluster deployment, configure the cluster-wide proxy:"
    echo ""
    echo "  HTTP_PROXY:  http://${LZ_PROXY_IP}:${PROXY_PORT}"
    echo "  HTTPS_PROXY: http://${LZ_PROXY_IP}:${PROXY_PORT}"
    echo "  NO_PROXY:    .cluster.local,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    echo ""
    echo "The proxy allows access to (per Red Hat documentation):"
    echo "  - Red Hat registries: registry.redhat.io, quay.io, cdn.quay.io"
    echo "  - Red Hat services: sso.redhat.com, access.redhat.com, console.redhat.com"
    echo "  - OpenShift APIs: api.openshift.com, mirror.openshift.com"
    echo "  - Telemetry: observatorium.api.openshift.com"
    echo "  - Google Cloud: *.googleapis.com, *.gcr.io, *.pkg.dev"
    echo "  - Docker Hub: registry-1.docker.io, auth.docker.io"
    echo "  - GitHub: github.com, raw.githubusercontent.com"
    echo "  - CDNs: *.cloudfront.net, *.amazonaws.com"
    echo ""
    echo "Reference: https://docs.redhat.com/en/documentation/openshift_dedicated/4/html-single/planning_your_environment/index#osd-gcp-psc-firewall-prerequisites_gcp-ccs"
    echo ""
    echo "=============================================="
    echo ""
    echo "ACCESSING THE CLUSTER:"
    echo "=============================================="
    echo ""
    echo "After cluster is deployed, run the DNS peering command to enable"
    echo "automatic DNS resolution from the proxy/bastion VM:"
    echo ""
    echo "  # Find the cluster's private DNS zone (created by OSD installer)"
    echo "  PRIVATE_ZONE=\$(gcloud dns managed-zones list --project=$PROJECT_ID \\"
    echo "    --filter='visibility=private AND name~private-zone' \\"
    echo "    --format='value(name)' | head -1)"
    echo ""
    echo "  # Add landing zone VPC to the private DNS zone"
    echo "  gcloud dns managed-zones update \$PRIVATE_ZONE \\"
    echo "    --project=$PROJECT_ID \\"
    echo "    --networks=$LZ_VPC_NAME,$OSD_VPC_NAME"
    echo ""
    echo "Then SSH to proxy/bastion:"
    echo "  gcloud compute ssh $LZ_PROXY_NAME \\"
    echo "    --project=$PROJECT_ID \\"
    echo "    --zone=${REGION}-a \\"
    echo "    --tunnel-through-iap"
    echo ""
    echo "=============================================="
}

# Configure DNS peering to enable cluster DNS resolution from landing zone VPC
configure_dns_peering() {
    log_info "Configuring DNS peering for cluster access..."
    
    # Find the cluster's private DNS zone
    local PRIVATE_ZONE=$(gcloud dns managed-zones list --project="$PROJECT_ID" \
        --filter="visibility=private AND name~${CLUSTER_NAME}.*private-zone" \
        --format="value(name)" 2>/dev/null | head -1)
    
    if [ -z "$PRIVATE_ZONE" ]; then
        log_warning "No private DNS zone found for cluster $CLUSTER_NAME"
        log_info "This is expected if the cluster hasn't been deployed yet."
        log_info "Run this script with --configure-dns after cluster deployment."
        return 1
    fi
    
    log_info "Found private DNS zone: $PRIVATE_ZONE"
    
    # Get current networks attached to the zone
    local CURRENT_NETWORKS=$(gcloud dns managed-zones describe "$PRIVATE_ZONE" \
        --project="$PROJECT_ID" \
        --format="value(privateVisibilityConfig.networks[].networkUrl)" 2>/dev/null)
    
    # Check if landing zone VPC is already attached
    if echo "$CURRENT_NETWORKS" | grep -q "$LZ_VPC_NAME"; then
        log_warning "Landing zone VPC is already attached to DNS zone $PRIVATE_ZONE"
        return 0
    fi
    
    # Add landing zone VPC to the private DNS zone
    log_info "Adding landing zone VPC to DNS zone: $PRIVATE_ZONE"
    gcloud dns managed-zones update "$PRIVATE_ZONE" \
        --project="$PROJECT_ID" \
        --networks="$LZ_VPC_NAME,$OSD_VPC_NAME"
    
    if [ $? -eq 0 ]; then
        log_success "DNS peering configured! Proxy VM can now resolve cluster hostnames."
        
        # Test DNS resolution from proxy
        log_info "Testing DNS resolution from proxy VM..."
        gcloud compute ssh "$LZ_PROXY_NAME" \
            --project="$PROJECT_ID" \
            --zone="${REGION}-a" \
            --tunnel-through-iap \
            --command="nslookup api.${CLUSTER_NAME}.*.openshiftapps.com 2>/dev/null | head -5 || echo 'DNS test complete'" 2>/dev/null || true
    else
        log_error "Failed to configure DNS peering"
        return 1
    fi
}

# Print Terraform configuration helper
print_terraform_config() {
    echo ""
    echo "=============================================="
    echo "     Terraform Configuration Reference"
    echo "=============================================="
    echo ""
    cat << EOF
# Add to your terraform.tfvars:

gcp_project = "$PROJECT_ID"
gcp_region = "$REGION"
gcp_zone = "${REGION}-a"
clustername = "$CLUSTER_NAME"

# Use existing VPC created by this script
use_existing_vpc = true
existing_vpc_name = "$OSD_VPC_NAME"
existing_master_subnet_name = "$OSD_MASTER_SUBNET_NAME"
existing_worker_subnet_name = "$OSD_WORKER_SUBNET_NAME"
existing_psc_subnet_name = "$OSD_PSC_SUBNET_NAME"
existing_router_name = "$OSD_ROUTER_NAME"

# Disable NAT gateway creation (using Landing Zone proxy for egress)
enable_nat_gateway = false

# Network configuration (matching pre-created subnets)
master_cidr_block = "$OSD_MASTER_CIDR"
worker_cidr_block = "$OSD_WORKER_CIDR"
psc_subnet_cidr_block = "$OSD_PSC_CIDR"
bastion_cidr_block = "$OSD_BASTION_CIDR"

# Private cluster with PSC
osd_gcp_private = true
osd_gcp_psc = true

# Proxy settings for cluster
# http_proxy = "http://${LZ_PROXY_IP}:${PROXY_PORT}"
# https_proxy = "http://${LZ_PROXY_IP}:${PROXY_PORT}"
# no_proxy = ".cluster.local,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

# Other settings
vpc_routing_mode = "REGIONAL"
EOF
    echo ""
    echo "=============================================="
    echo ""
    echo "To configure proxy in OpenShift after deployment:"
    echo ""
    echo "  oc edit proxy cluster"
    echo ""
    echo "Then add:"
    echo "  spec:"
    echo "    httpProxy: http://${LZ_PROXY_IP}:${PROXY_PORT}"
    echo "    httpsProxy: http://${LZ_PROXY_IP}:${PROXY_PORT}"
    echo "    noProxy: .cluster.local,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    echo ""
    echo "=============================================="
}

# Main execution
main() {
    echo ""
    echo "=============================================="
    echo "   OSD Private VPC Infrastructure Setup"
    echo "=============================================="
    echo ""
    
    if [ "$DELETE_MODE" = true ]; then
        log_warning "Running in DELETE mode. This will remove all infrastructure."
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Aborted."
            exit 0
        fi
        delete_infrastructure
    elif [ "$CONFIGURE_DNS_MODE" = true ]; then
        log_info "Running in DNS configuration mode."
        configure_dns_peering
    else
        # Create infrastructure
        create_landing_zone_vpc
        echo ""
        create_squid_proxy
        echo ""
        create_osd_vpc
        echo ""
        create_vpc_peering
        echo ""
        print_summary
        print_terraform_config
    fi
}

# Run main
main
