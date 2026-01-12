#!/bin/bash

# =============================================================================
# OSD on GCP - Prerequisites Check Script
# =============================================================================
# Run this script before deployment to verify all prerequisites are met.
# Based on Red Hat documentation:
# https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/planning_your_environment/gcp-ccs
# Usage: ./scripts/check-prereqs.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Parse arguments
SKIP_NETWORK=false
VERBOSE=false
for arg in "$@"; do
    case $arg in
        --skip-network) SKIP_NETWORK=true ;;
        --verbose|-v) VERBOSE=true ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --skip-network  Skip network connectivity checks"
            echo "  --verbose, -v   Show verbose output"
            echo "  --help, -h      Show this help"
            exit 0
            ;;
    esac
done

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_subheader() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
}

check_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    ((WARNINGS++))
}

check_info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}ℹ INFO:${NC} $1"
    fi
}

# =============================================================================
# Check Required Tools
# =============================================================================
print_header "Checking Required Tools"

# Check OCM CLI
if command -v ocm &> /dev/null; then
    OCM_VERSION=$(ocm version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    REQUIRED_VERSION="0.1.73"
    if [ "$OCM_VERSION" != "unknown" ] && [ "$(printf '%s\n' "$REQUIRED_VERSION" "$OCM_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
        check_pass "OCM CLI installed (version: $OCM_VERSION)"
    else
        check_fail "OCM CLI version $OCM_VERSION is too old (requires >= $REQUIRED_VERSION)"
        echo "       Download from: https://github.com/openshift-online/ocm-cli/releases"
    fi
else
    check_fail "OCM CLI not installed"
    echo "       Download from: https://github.com/openshift-online/ocm-cli/releases"
fi

# Check Terraform
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    check_pass "Terraform installed (version: $TF_VERSION)"
else
    check_fail "Terraform not installed"
    echo "       Install from: https://www.terraform.io/downloads"
fi

# Check gcloud
if command -v gcloud &> /dev/null; then
    GCLOUD_VERSION=$(gcloud version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "installed")
    check_pass "gcloud CLI installed (version: $GCLOUD_VERSION)"
else
    check_fail "gcloud CLI not installed"
    echo "       Install from: https://cloud.google.com/sdk/docs/install"
fi

# Check jq
if command -v jq &> /dev/null; then
    JQ_VERSION=$(jq --version 2>/dev/null || echo "installed")
    check_pass "jq installed ($JQ_VERSION)"
else
    check_fail "jq not installed"
    echo "       Install: brew install jq (macOS) or apt-get install jq (Linux)"
fi

# =============================================================================
# Check OCM Authentication
# =============================================================================
print_header "Checking OCM Authentication"

if command -v ocm &> /dev/null; then
    if ocm whoami &> /dev/null; then
        OCM_USER=$(ocm whoami 2>/dev/null | grep -E "^(Username|Account):" | head -1 || echo "authenticated")
        check_pass "OCM logged in ($OCM_USER)"
        
        # Check OCM token expiry (if possible)
        TOKEN_INFO=$(ocm token 2>/dev/null || true)
        if [ -n "$TOKEN_INFO" ]; then
            check_pass "OCM token is valid"
        fi
    else
        check_fail "OCM not logged in"
        echo "       Run: ocm login --token=<your-token-from-console.redhat.com>"
        echo "       Get token from: https://console.redhat.com/openshift/token"
    fi
else
    check_warn "Cannot check OCM auth - OCM CLI not installed"
fi

# =============================================================================
# Check GCP Authentication
# =============================================================================
print_header "Checking GCP Authentication"

if command -v gcloud &> /dev/null; then
    # Check gcloud auth
    GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
    if [ -n "$GCLOUD_ACCOUNT" ] && [ "$GCLOUD_ACCOUNT" != "(unset)" ]; then
        check_pass "gcloud authenticated as: $GCLOUD_ACCOUNT"
    else
        check_fail "gcloud not authenticated"
        echo "       Run: gcloud auth login"
    fi

    # Check application-default credentials
    if gcloud auth application-default print-access-token &> /dev/null; then
        check_pass "gcloud application-default credentials configured"
    else
        check_warn "gcloud application-default credentials not set"
        echo "       Run: gcloud auth application-default login"
    fi

    # Check GCP project
    GCP_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$GCP_PROJECT" ] && [ "$GCP_PROJECT" != "(unset)" ]; then
        check_pass "GCP project configured: $GCP_PROJECT"
    else
        check_warn "GCP project not set in gcloud config"
        echo "       Run: gcloud config set project YOUR_PROJECT_ID"
    fi
fi

# =============================================================================
# Check GCP APIs (if project is set)
# Per Red Hat docs: https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/planning_your_environment/gcp-ccs
# =============================================================================
print_header "Checking GCP APIs"

if command -v gcloud &> /dev/null && [ -n "$GCP_PROJECT" ] && [ "$GCP_PROJECT" != "(unset)" ]; then
    # Required APIs per Red Hat documentation
    REQUIRED_APIS=(
        "compute.googleapis.com"
        "iam.googleapis.com"
        "iamcredentials.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "serviceusage.googleapis.com"
        "storage.googleapis.com"
        "dns.googleapis.com"
        "servicenetworking.googleapis.com"
    )
    
    # Additional recommended APIs
    RECOMMENDED_APIS=(
        "container.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    ENABLED_APIS=$(gcloud services list --enabled --format="value(config.name)" 2>/dev/null || echo "")
    
    print_subheader "Required APIs"
    for API in "${REQUIRED_APIS[@]}"; do
        if echo "$ENABLED_APIS" | grep -q "^$API$"; then
            check_pass "API enabled: $API"
        else
            check_fail "API not enabled: $API"
            echo "       Run: gcloud services enable $API"
        fi
    done
    
    print_subheader "Recommended APIs"
    for API in "${RECOMMENDED_APIS[@]}"; do
        if echo "$ENABLED_APIS" | grep -q "^$API$"; then
            check_pass "API enabled: $API"
        else
            check_warn "API not enabled (recommended): $API"
            echo "       Run: gcloud services enable $API"
        fi
    done
else
    check_warn "Cannot check GCP APIs - project not configured"
fi

# =============================================================================
# Check Authentication Type Configuration
# =============================================================================
print_header "Checking OSD Authentication Configuration"

# Check TF_VAR_gcp_authentication_type
if [ -n "$TF_VAR_gcp_authentication_type" ]; then
    check_pass "Authentication type set: $TF_VAR_gcp_authentication_type"
    
    if [ "$TF_VAR_gcp_authentication_type" = "workload_identity_federation" ]; then
        check_pass "Using Workload Identity Federation (recommended)"
    elif [ "$TF_VAR_gcp_authentication_type" = "service_account" ]; then
        check_warn "Using Service Account authentication"
        echo "       Consider using WIF for better security"
    fi
else
    check_warn "TF_VAR_gcp_authentication_type not set (defaults to service_account)"
    echo "       Recommended: export TF_VAR_gcp_authentication_type=workload_identity_federation"
fi

# =============================================================================
# Check Cluster Name
# =============================================================================
print_header "Checking Cluster Configuration"

if [ -n "$TF_VAR_clustername" ]; then
    check_pass "Cluster name set: $TF_VAR_clustername"
    
    # Check if cluster already exists
    if command -v ocm &> /dev/null && ocm whoami &> /dev/null; then
        EXISTING=$(ocm get /api/clusters_mgmt/v1/clusters --parameter search="name = '$TF_VAR_clustername'" 2>/dev/null | jq -r '.items[0].name // empty')
        if [ -n "$EXISTING" ]; then
            check_warn "Cluster '$TF_VAR_clustername' already exists in OCM!"
        else
            check_pass "Cluster name '$TF_VAR_clustername' is available"
        fi
    fi
else
    check_fail "TF_VAR_clustername not set"
    echo "       Run: export TF_VAR_clustername=your-cluster-name"
fi

# =============================================================================
# Check SSH Key (for bastion)
# =============================================================================
print_header "Checking SSH Key (for Bastion)"

SSH_KEY_LOC="${TF_VAR_bastion_key_loc:-~/.ssh/id_rsa.pub}"
SSH_KEY_LOC_EXPANDED=$(eval echo "$SSH_KEY_LOC")

if [ -f "$SSH_KEY_LOC_EXPANDED" ]; then
    check_pass "SSH public key found: $SSH_KEY_LOC"
else
    check_warn "SSH public key not found: $SSH_KEY_LOC"
    echo "       Generate with: ssh-keygen -t rsa -b 4096"
    echo "       Or set: export TF_VAR_bastion_key_loc=/path/to/your/key.pub"
fi

# =============================================================================
# Check tfvars file
# =============================================================================
print_header "Checking Terraform Configuration"

TFVARS_FILE="configuration/tfvars/terraform.tfvars"
if [ -f "$TFVARS_FILE" ]; then
    check_pass "terraform.tfvars exists"
    
    # Check for required variables
    if grep -q "gcp_project" "$TFVARS_FILE" 2>/dev/null; then
        GCP_PROJECT_VAR=$(grep "gcp_project" "$TFVARS_FILE" | grep -v "^#" | head -1 || true)
        if [ -n "$GCP_PROJECT_VAR" ]; then
            check_pass "gcp_project configured in tfvars"
        else
            check_warn "gcp_project appears to be commented out"
        fi
    else
        check_fail "gcp_project not found in tfvars"
    fi
else
    check_fail "terraform.tfvars not found"
    echo "       Run: cp configuration/tfvars/terraform.tfvars.example configuration/tfvars/terraform.tfvars"
fi

# =============================================================================
# Check Network Connectivity (Firewall Prerequisites)
# Per Red Hat docs: Required URLs must be accessible
# https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/planning_your_environment/gcp-ccs#osd-gcp-firewall-prerequisites_gcp-ccs
# =============================================================================
if [ "$SKIP_NETWORK" = false ]; then
    print_header "Checking Network Connectivity (Firewall Prerequisites)"
    echo "Testing connectivity to required Red Hat and GCP endpoints..."
    echo "(Use --skip-network to skip these checks)"
    echo ""
    
    # Function to check URL connectivity
    check_url() {
        local url=$1
        local description=$2
        local timeout=5
        
        if curl -s --connect-timeout $timeout --max-time $timeout -o /dev/null -w "%{http_code}" "https://$url" 2>/dev/null | grep -qE "^(2|3|4)[0-9][0-9]$"; then
            check_pass "Reachable: $url"
            return 0
        else
            check_fail "Cannot reach: $url ($description)"
            return 1
        fi
    }
    
    print_subheader "Red Hat OpenShift Services (Required)"
    # Critical Red Hat services
    check_url "api.openshift.com" "OCM API - cluster management" || true
    check_url "sso.redhat.com" "Red Hat SSO - authentication" || true
    check_url "console.redhat.com" "Red Hat Console - cluster management" || true
    
    print_subheader "Container Registries (Required)"
    check_url "quay.io" "Quay.io - container images" || true
    check_url "registry.redhat.io" "Red Hat Registry - container images" || true
    check_url "registry.access.redhat.com" "Red Hat Registry - container images" || true
    check_url "registry.connect.redhat.com" "Red Hat Partner Registry - certified operators" || true
    
    print_subheader "Telemetry Endpoints (Required for Support)"
    check_url "cert-api.access.redhat.com" "Telemetry" || true
    check_url "api.access.redhat.com" "Telemetry" || true
    check_url "infogw.api.openshift.com" "Telemetry" || true
    
    print_subheader "Google Cloud APIs (Required)"
    check_url "accounts.google.com" "Google authentication" || true
    check_url "storage.googleapis.com" "Google Cloud Storage API" || true
    check_url "iam.googleapis.com" "Google IAM API" || true
    check_url "compute.googleapis.com" "Google Compute API" || true
    check_url "dns.googleapis.com" "Google DNS API" || true
    check_url "cloudresourcemanager.googleapis.com" "Google Cloud Resource Manager API" || true
    check_url "iamcredentials.googleapis.com" "Google IAM Credentials API" || true
    check_url "serviceusage.googleapis.com" "Google Service Usage API" || true
    
    print_subheader "Additional OpenShift Services"
    check_url "mirror.openshift.com" "OpenShift mirror - installation content" || true
else
    print_header "Network Connectivity Checks"
    echo -e "${YELLOW}Skipped (--skip-network flag provided)${NC}"
fi

# =============================================================================
# Check WIF Configuration (for Workload Identity Federation auth)
# =============================================================================
print_header "Checking WIF Configuration"

if [ "$TF_VAR_gcp_authentication_type" = "workload_identity_federation" ] || [ -z "$TF_VAR_gcp_authentication_type" ]; then
    if command -v ocm &> /dev/null && ocm whoami &> /dev/null; then
        # Check existing WIF configs
        echo "Checking for existing WIF configurations..."
        WIF_LIST=$(ocm gcp list wif-configs 2>/dev/null || echo "")
        
        if [ -n "$WIF_LIST" ]; then
            WIF_COUNT=$(echo "$WIF_LIST" | grep -c "^" || echo "0")
            check_pass "Found $WIF_COUNT WIF configuration(s) in OCM"
            
            # If cluster name is set, check if WIF for this cluster exists
            if [ -n "$TF_VAR_clustername" ]; then
                EXPECTED_WIF="${TF_VAR_clustername}-wif"
                if echo "$WIF_LIST" | grep -q "$EXPECTED_WIF"; then
                    check_pass "WIF config '$EXPECTED_WIF' already exists"
                else
                    check_info "WIF config '$EXPECTED_WIF' will be created during deployment"
                fi
            fi
        else
            check_info "No existing WIF configurations (will be created during deployment)"
        fi
        
        # Check if GCP project is configured for WIF
        if [ -n "$GCP_PROJECT" ] && [ "$GCP_PROJECT" != "(unset)" ]; then
            check_pass "GCP project configured for WIF: $GCP_PROJECT"
        else
            check_warn "GCP project should be set for WIF deployment"
        fi
    else
        check_warn "Cannot check WIF configs - OCM not authenticated"
    fi
else
    echo "Using service_account authentication - WIF check skipped"
fi

# =============================================================================
# Summary
# =============================================================================
print_header "Summary"

echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASSED"
echo -e "  ${RED}Failed:${NC}   $FAILED"
echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All critical prerequisites are met!${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}Please review warnings above before proceeding.${NC}"
    fi
    echo ""
    echo "You can proceed with deployment:"
    echo "  make all"
    echo ""
    exit 0
else
    echo -e "${RED}Some prerequisites are not met. Please fix the issues above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "  • OCM login:     ocm login --token=<token-from-console.redhat.com>"
    echo "  • GCP auth:      gcloud auth login && gcloud auth application-default login"
    echo "  • Enable APIs:   gcloud services enable compute.googleapis.com iam.googleapis.com ..."
    echo "  • Set project:   gcloud config set project YOUR_PROJECT_ID"
    echo "  • Set auth type: export TF_VAR_gcp_authentication_type=workload_identity_federation"
    echo ""
    echo "Documentation:"
    echo "  https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/planning_your_environment/gcp-ccs"
    echo ""
    exit 1
fi

# =============================================================================
# Prerequisites Reference (from Red Hat documentation)
# =============================================================================
# 
# Required GCP APIs:
#   - compute.googleapis.com
#   - iam.googleapis.com  
#   - iamcredentials.googleapis.com
#   - cloudresourcemanager.googleapis.com
#   - serviceusage.googleapis.com
#   - storage.googleapis.com
#   - dns.googleapis.com
#
# Required Network Access (Firewall):
#   - api.openshift.com (443) - OCM API
#   - sso.redhat.com (443) - Authentication
#   - quay.io (443) - Container images
#   - registry.redhat.io (443) - Container images
#   - registry.access.redhat.com (443) - Container images
#   - console.redhat.com (443) - Cluster management
#   - *.googleapis.com (443) - Google Cloud APIs
#
# WIF (Workload Identity Federation):
#   - WIF config is automatically created during deployment
#   - Uses short-lived credentials (more secure than service account keys)
#   - Requires GCP project to be configured
#
# Source: https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/planning_your_environment/gcp-ccs
# =============================================================================
