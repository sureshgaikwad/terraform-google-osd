# ============================================
# OSD on GCP - Terraform Configuration
# ============================================

# ============================================
# GCP Project & Cluster Settings
# ============================================
gcp_project = "mobb-demo"
clustername = "sgaikwad"
gcp_region  = "asia-south1"
gcp_zone    = "asia-south1-a"

# ============================================
# Authentication Configuration
# ============================================
# Options: "service_account" or "workload_identity_federation"
gcp_authentication_type = "workload_identity_federation"

# Service Account JSON path (required for service_account auth)
# gcp_sa_file_loc = "~/.ssh/osd-ccs-admin.json"

# ============================================
# WIF Configuration
# ============================================
# Set to true to use existing WIF instead of creating new
use_existing_wif = true

# Name of existing WIF config (required when use_existing_wif = true)
existing_wif_config_name = "sgaikwad-wifi"

# ============================================
# VPC Configuration
# ============================================
vpc_routing_mode = "REGIONAL"

# CIDR blocks (used when creating new VPC)
master_cidr_block     = "10.0.0.0/19"
worker_cidr_block     = "10.0.32.0/19"
psc_subnet_cidr_block = "10.0.64.0/29"
bastion_cidr_block    = "10.10.0.0/24"

# ============================================
# Existing VPC Configuration
# Set use_existing_vpc = true to use pre-created VPC
# ============================================
use_existing_vpc             = true
existing_vpc_name            = "sgaikwad-vpc"
existing_master_subnet_name  = "sgaikwad-master-subnet"
existing_worker_subnet_name  = "sgaikwad-worker-subnet"
existing_psc_subnet_name     = "sgaikwad-psc-subnet"
existing_router_name         = "sgaikwad-router"

# ============================================
# NAT Gateway Configuration
# ============================================
# Set to false when using landing zone / hub-spoke architecture
enable_nat_gateway = false

# ============================================
# Proxy Configuration (for private VPC without NAT)
# ============================================
# Required when enable_nat_gateway = false and using hub-spoke architecture
http_proxy  = "http://10.100.0.10:3128"
https_proxy = "http://10.100.0.10:3128"
no_proxy    = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.169.254"
# additional_trust_bundle = ""  # Path to CA bundle if proxy uses custom cert

# ============================================
# Cluster Type Configuration
# ============================================
osd_gcp_private = true
osd_gcp_psc     = true

# PSC endpoints (used when osd_gcp_psc = true)
enable_psc_endpoints = [
  "storage.googleapis.com",
  "container.googleapis.com",
  "compute.googleapis.com",
  "logging.googleapis.com",
  "monitoring.googleapis.com"
]

# ============================================
# Multi-AZ Configuration
# ============================================
# Comma-separated zones for multi-AZ deployment
# Leave empty for single-zone
gcp_availability_zones = "asia-south1-a,asia-south1-b,asia-south1-c"

# Number of compute nodes (must be multiple of zone count for multi-AZ)
# Leave as null for OCM defaults
compute_nodes_count = 3

# ============================================
# Bastion Host Configuration
# ============================================
# Set to false - bastion will be created in hub VPC separately
enable_osd_gcp_bastion = false
# bastion_machine_type   = "e2-micro"
# bastion_key_loc        = "~/.ssh/id_ed25519.pub"

# ============================================
# Advanced Options
# ============================================
# Deploy only infrastructure without OSD cluster
only_deploy_infra_no_osd = false
