# OpenShift Dedicated for GCP in Pre-Existing VPCs & in Private Mode

Automation Code for deploy and manage OpenShift Dedicated in GCP in Pre-Existing VPCs & Private Mode

### Authentication

Pick one of two options for the installer and cluster to access GCP resources in your account, Workload Identity Federation, or Service Account.

#### Workload Identity Federation

[Workload Identity Federation](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-cluster-with-workload-identity-federation.html#workload-identity-federation-overview_osd-creating-a-cluster-on-gcp-with-workload-identity-federation) is the preferred method of authentication that uses short-lived credentials.

1. Follow the general [Required customer procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure_gcp-ccs)
1. Follow the specific [Workload Identity Federation authentication type procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure-wif_gcp-ccs)
1. Set the `gcp_authentication_type` Terraform variable using `export TF_VAR_gcp_authentication_type=workload_identity_federation`.
1. Optionally, if you have configured a bastion, and your ssh key is not `~/.ssh/id_rsa.pub`, set its location using ` export TF_VAR_bastion_key_loc=$PATH_TO_PUBLIC_KEY`

#### Service Account

[Service Account](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-cluster-sa.html#service-account-auth-overview_osd-creating-a-cluster-on-gcp-sa) authentication uses a public/private keypair with broader permissions than WIF.

1. Follow the general [Required customer procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure_gcp-ccs)
1. Follow the specific [Service account authentication type procedure](https://docs.openshift.com/dedicated/osd_planning/gcp-ccs.html#ccs-gcp-customer-procedure-sa_gcp-ccs)
1. Export the location of your `osd-ccs-admin` service account key json file using `export TF_VAR_gcp_sa_file_loc=$PATH_TO_JSON_FILE`
1. Set the `gcp_authentication_type` Terraform variable using `export TF_VAR_gcp_authentication_type=service_account`.
1. Optionally, if you have configured a bastion, and your ssh key is not `~/.ssh/id_rsa.pub`, set its location using ` export TF_VAR_bastion_key_loc=$PATH_TO_PUBLIC_KEY`

## OSD in GCP in Pre-Existing VPCs / Subnets (ideally use the terraform below)

<img align="center" width="750" src="assets/osd-prereqs.png">

* Copy and modify the tfvars file in order to custom to your scenario

```bash
cp -pr configuration/tfvars/terraform.tfvars.example configuration/tfvars/terraform.tfvars
```

## OSD in GCP building everything from scratch (automation yay!)

* Deploy everything using terraform and ocm:

Ensure you have the following installed:
* `ocm` binary, at least version 1.0.3, logged in
* `jq`
* `gcloud` binary, logged in

* Ensure you have the following exported:

```bash
export TF_VAR_clustername=$YOUR_CLUSTER_NAME
export TF_VAR_gcp_sa_file_loc=$PATH_TO_YOUR_SA_JSON
````

Then:

```bash
make all
```

This will:
1. Build your VPCs based on the config  in configuration/tfvars
2. Connect to your ocm console and create a new cluster using the variables from terraform

You should then be good to go!

## Or if you want to do it manually:

```bash
export ENVIRONMENT="lab"
export TF_BACKEND_CONF="configuration/backend"
export TF_VARIABLES="configuration/tfvars"
export TF_VAR_clustername=$YOUR_CLUSTER_NAME

terraform init -backend-config="$TF_BACKEND_CONF/$ENVIRONMENT.conf"
terraform plan -var-file="$TF_VARIABLES/terraform.tfvars" -out "output/tf.$ENVIRONMENT.plan"
terraform apply output/tf.$ENVIRONMENT.plan
```

* Then follow the [OSD in GCP install link](https://docs.openshift.com/dedicated/osd_install_access_delete_cluster/creating-a-gcp-cluster.html#osd-create-gcp-cluster-ccs_osd-creating-a-cluster-on-gcp)

## OSD in GCP in Private Mode

<img align="center" width="750" src="assets/osd-prereqs-private.png">

NOTE: this will be deploying also the Bastion host that will be used for connect to the OSD private cluster.

* Setup to true these two variables, in your terraform.tfvars.

```bash
enable_osd_gcp_bastion = true
osd_gcp_private = true
```

* Deploy the network infrastructure in GCP needed for deploy the OSD cluster

```bash
make all
```

* or if you want to do it manually:

```bash
export ENVIRONMENT="lab"
export TF_BACKEND_CONF="configuration/backend"
export TF_VARIABLES="configuration/tfvars"

terraform init -backend-config="$TF_BACKEND_CONF/$ENVIRONMENT.conf"
terraform plan -var-file="$TF_VARIABLES/terraform.tfvars" -out "output/tf.$ENVIRONMENT.plan"
terraform apply output/tf.$ENVIRONMENT.plan
```

* Follow the [OSD in GCP install link](https://docs.openshift.com/dedicated/osd_install_access_delete_cluster/creating-a-gcp-cluster.html#osd-create-gcp-cluster-ccs_osd-creating-a-cluster-on-gcp)

## Auto cleanup

Export the following:

```bash
export TF_VAR_clustername=$YOUR_CLUSTER_NAME
````

Then:

```bash
make destroy
```


## OSD in GCP with Private Service Connect (PSC)

[Private Service Connect (PSC)](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-psc-enabled-private-cluster.html) is Google Cloud's security-enhanced networking feature that enables private communication between services across different projects or organizations within GCP. With PSC, you can deploy OpenShift Dedicated clusters in a completely private environment without any public-facing cloud resources.

### Prerequisites

* PSC is only available on OpenShift Dedicated version 4.17 and later
* Must use Customer Cloud Subscription (CCS) model
* Requires Workload Identity Federation (WIF) or Service Account authentication
* Cloud Identity-Aware Proxy API must be enabled in your GCP project
* **OCM CLI version 0.1.73 or later** (required for PSC support)
  ```bash
  # Check version
  ocm version
  
  # If upgrade needed:
  wget https://github.com/openshift-online/ocm-cli/releases/download/v0.1.73/ocm-linux-amd64
  ```

### Setup PSC-enabled Private Cluster

* Copy and modify the PSC example tfvars file:

```bash
cp -pr configuration/tfvars/terraform.tfvars.psc.example configuration/tfvars/terraform.tfvars
```

* Key configuration in your terraform.tfvars:

```bash
# enable private cluster with PSC
osd_gcp_private = true
osd_gcp_psc = true

# PSC requires WIF authentication (recommended)
gcp_authentication_type = "workload_identity_federation"

# enable bastion for private cluster access
enable_osd_gcp_bastion = true

# IMPORTANT: PSC subnet MUST be within Machine CIDR range
# example with proper CIDR allocation:
master_cidr_block = "10.0.0.0/19"      # 10.0.0.0 - 10.0.31.255
worker_cidr_block = "10.0.32.0/19"     # 10.0.32.0 - 10.0.63.255
psc_subnet_cidr_block = "10.0.64.0/29" # within Machine CIDR (10.0.0.0/17)

# CRITICAL: Ensure naming consistency!
clustername = "osd-psc-wif"  # must match what you'll use in OCM
```

* **Export environment variable to ensure naming consistency**:

```bash
export TF_VAR_clustername=osd-psc-wif  # must match terraform.tfvars
```

* Deploy the infrastructure and cluster:

```bash
make all
```

This will:
- Automatically create WIF config as `${clustername}-wif`
- Deploy VPCs, subnets, and firewall rules
- Create the OSD cluster with PSC
- Monitor installation progress (typically 30-45 minutes)

### Accessing the PSC Private Cluster

Once the cluster is ready (State: ready), access it through the bastion:

#### 1. SSH to bastion
```bash
gcloud compute ssh ${CLUSTERNAME}-bastion-vm --zone=${GCP_ZONE} --project=${GCP_PROJECT}
```

#### 2. Install OCM CLI on bastion (if not already installed)
```bash
wget https://github.com/openshift-online/ocm-cli/releases/download/v0.1.73/ocm-linux-amd64
sudo mv ocm-linux-amd64 /usr/bin/ocm
sudo chmod +x /usr/bin/ocm
```

#### 3. Test API connectivity
```bash
# find API endpoint
nslookup api.${CLUSTERNAME}.<domain>.openshiftapps.com

# test health endpoint (should return "ok")
curl -k https://api.${CLUSTERNAME}.<domain>.openshiftapps.com:6443/healthz
```

#### 4. Configure Identity Provider 
Since OAuth endpoints are not accessible from the internet, you must configure an IdP from your local machine:

**From your local browser:**
1. Go to https://console.redhat.com
2. Find your cluster
3. Navigate to "Access control" → "Identity providers"
4. Add an IdP (recommended: htpasswd for quick setup)
   - Click "Add identity provider" → "HTPasswd"
   - Give it a name (e.g., "cluster-admin")
   - Add users with passwords
5. Grant admin access:
   - Go to "Access control" → "Cluster roles and access"
   - Click "Add user"
   - Select your user and assign "cluster-admin" role

#### 5. Access your cluster from bastion
```bash
# login to OCM from bastion (use device code since no browser)
ocm login --use-device-code
# follow the instructions to authenticate via your local browser

# example direct login with your htpasswd credentials
oc login https://api.${CLUSTERNAME}.<domain>.openshiftapps.com:6443 \
  --username=<your-htpasswd-username> \
  --password=<your-htpasswd-password> \
  --insecure-skip-tls-verify=true
```

#### 6. Verify successful deployment
```bash
# check you're logged in correctly
oc whoami
# output: <your-htpasswd-username>

# verify all nodes are ready
oc get nodes
# output should show all nodes in Ready state:
# NAME                                          STATUS   ROLES                  AGE
# osd-psc-wif-xxxxx-master-0.c.project.internal   Ready    control-plane,master   4h
# osd-psc-wif-xxxxx-master-1.c.project.internal   Ready    control-plane,master   4h
# osd-psc-wif-xxxxx-master-2.c.project.internal   Ready    control-plane,master   4h
# osd-psc-wif-xxxxx-worker-a-xxxxx...             Ready    worker                 4h

# confirm PSC and API server pods are running
oc get pods -A | grep -E "(psc|apiserver)"
# should show multiple pods in Running state

# check the API service endpoint
oc get svc -n openshift-kube-apiserver
# should show the kubernetes service with ClusterIP
```

### Important PSC Notes

**CIDR Planning is Critical**:
- PSC subnet MUST be within Machine CIDR range (master + worker combined)
- PSC subnet requires /29 or larger
- Plan your CIDR allocations carefully - overlapping ranges will cause deployment failures

**Network Access**:
- OAuth endpoints only accessible from private network (not from internet)
- Configure identity provider before attempting cluster access (do this via console)
- Bastion host is required for private cluster management

**Firewall Rules and Tags**:
- OSD adds random suffixes to instance tags (e.g., `osd-cluster-name-abc123-worker`)
- Terraform firewall rules now use IP ranges instead of tags to ensure connectivity
- This avoids issues where Terraform-defined tags don't match OSD-created instance tags

**Cluster Naming**:
- Ensure the cluster name used in `ocm create cluster` matches your Terraform `clustername` variable
- Consistency is important for resource naming and identification

### Troubleshooting

#### API Connection Timeout from Bastion

If you cannot reach the API from the bastion:

1. **Verify firewall rules are in correct VPC**:
```bash
# find which VPC your cluster is in
VPC_NAME=$(gcloud compute instances describe <master-instance-name> --zone=${ZONE} --format="value(networkInterfaces[0].network.segment(-1))")

# list firewall rules for that VPC
gcloud compute firewall-rules list --filter="network:${VPC_NAME}"
```

2. **Check if bastion can reach masters**:
```bash
# from bastion, test master IPs directly
for ip in 10.0.0.3 10.0.0.4 10.0.0.5; do
  timeout 2 nc -zv $ip 6443 && echo "$ip: OK" || echo "$ip: FAILED"
done
```

3. **Common issues and solutions**:

| Issue | Cause | Solution |
|-------|-------|----------|
| Can't reach API from bastion | Firewall rules using wrong tags | Use IP-based rules (implemented in this repo) |
| 403 Forbidden from API | Normal - not authenticated | Configure IdP and login |
| DNS not resolving | Private DNS configuration | Check /etc/hosts or PSC DNS zones |
| Cluster name mismatch | Terraform var != OCM cluster name | Ensure `TF_VAR_clustername` matches |

### Architecture Details

With PSC enabled:
- Red Hat SRE access is provided through PSC service attachments
- No public IPs or NAT gateways required
- All traffic remains within Google's network
- Cluster API server only accessible via private endpoints
- Google APIs accessed through private PSC endpoints instead of public internet

For more details, see:
- [Private Service Connect overview](https://docs.openshift.com/dedicated/osd_gcp_clusters/creating-a-gcp-psc-enabled-private-cluster.html)
- [OpenShift Dedicated on GCP architecture models](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/architecture/osd-architecture-models-gcp)
- [Configuring IDP](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/authentication_and_authorization/sd-configuring-identity-providers)
- [Managing administration roles and users](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/authentication_and_authorization/osd-admin-roles)