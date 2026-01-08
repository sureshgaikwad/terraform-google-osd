
gcp_project = "mobb-demo"

clustername = "sgaikwad-new"

vpc_routing_mode = "REGIONAL"

master_cidr_block = "10.0.0.0/19"

worker_cidr_block = "10.0.32.0/19"

psc_subnet_cidr_block = "10.0.64.0/29"

bastion_cidr_block = "10.10.0.0/24"

gcp_region = "asia-south1"
gcp_zone = "asia-south1-a"

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

only_deploy_infra_no_osd = false

gcp_availability_zones = "asia-south1-a,asia-south1-b,asia-south1-c"

# Optional: Custom SSH key location for bastion (if not using default)
bastion_key_loc = "~/.ssh/id_ed25519.pub"

# Optional: Bastion machine type (default: e2-micro)
bastion_machine_type = "e2-micro"
