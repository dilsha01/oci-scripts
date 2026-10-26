# FortiGate HA Hub with OCI DRG Transit Routing

This Terraform configuration creates an active/passive FortiGate HA pair in an
existing OCI hub VCN. It creates the four firewall subnets, route tables,
optional gateways, a hub VCN DRG attachment, and (optionally) the IAM resources
needed by the FortiGate OCI Fabric Connector to move the floating IPs during a
failover.

It is intentionally **not** a complete landing-zone deployment: the hub VCN,
spoke VCNs, their workload subnets, their DRG attachments, and their security
rules must already exist or be managed separately.

## Before you run Terraform

1. Configure OCI authentication for the `oci` Terraform provider (for example,
   `~/.oci/config` and the provider environment variables, or another supported
   authentication method).
2. In OCI Marketplace, make sure the FortiGate BYOL image and the selected
   version are available in the target region. Terraform can accept the terms
   when `accept_marketplace_terms = true`, subject to the permissions of the
   identity running Terraform.
3. Choose non-overlapping CIDRs. The supplied configuration creates these
   hub subnets, so the hub VCN must contain `10.8.0.128/26` through
   `10.8.0.255/28` without overlap:

   | Purpose | CIDR | Notes |
   | --- | --- | --- |
   | Management (port1) | `10.8.0.128/26` | Public IPs are assigned to both firewalls. |
   | Indoor/trust (port2) | `10.8.0.192/27` | Contains the floating HA IP used as the inside next hop. |
   | Untrust/DMZ (port3) | `10.8.0.224/28` | Contains the floating HA IP and shared traffic public IP. |
   | Heartbeat (port4) | `10.8.0.240/28` | Private HA heartbeat network. |

   Change the hard-coded subnet and VNIC IP addresses in `network.tf` and
   `main.tf` together if those ranges do not fit the hub VCN. Do not only
   change `terraform.tfvars`—these particular CIDRs are currently in code.
4. Make sure the default security list used by the four new subnets permits the
   required administration, HA heartbeat/synchronization, and application
   flows. Security rules are not created by this configuration. Restrict GUI
   and SSH access to approved administrator source ranges.

## Values you must provide

Copy and edit `terraform.tfvars`; do not commit real OCIDs, private keys, or
the generated state files. At a minimum, replace these values with values from
your OCI tenancy:

| Variable | What you provide |
| --- | --- |
| `region` | Target OCI region, for example `ap-hyderabad-1`. |
| `tenancy_ocid` | Tenancy OCID. |
| `compartment_ocid` | Compartment for the instances, marketplace subscription, public IPs, and IAM policy resources. |
| `network_compartment_ocid` | Network compartment when it differs from `compartment_ocid`; otherwise leave it empty. |
| `vcn_ocid` | OCID of the existing hub VCN. |
| `vcn_name` | Display name of that same hub VCN. |
| `subnet_name` | Name of an existing subnet in the hub VCN. It is looked up by the current configuration, even though the firewall interfaces use the newly created subnets. |
| `fw01_indoor_ha_ip` | Unused address in the indoor subnet for the movable port2 IP. |
| `fw01_untrust_ha_ip` | Unused address in the untrust subnet for the movable port3 IP. |

Also review these values before applying:

| Setting | Decision to make |
| --- | --- |
| `shape`, `ocpus`, `memory_in_gbs`, `boot_volume_*` | Confirm capacity and quota for the selected availability domain. |
| `ad_index` | Select a valid availability domain index for the region. Both firewalls are deployed to that AD. |
| `image_source` and image variables | Use a valid Marketplace listing/package, or provide a compatible platform/custom image. |
| `ssh_public_key` | Supply your public key, or leave blank for Terraform to generate `<ssh_key_name>.key` locally. Store that generated private key securely. |
| Gateway OCIDs and `create_*_gateway` flags | Reuse existing IGW/NAT/Service Gateway/DRG by OCID, or allow Terraform to create them. Do not set an OCID and expect Terraform to manage that existing resource. |
| `create_iam_resources` | Leave `true` only if Terraform is allowed to create tenancy-level dynamic-group and policy resources. Otherwise create equivalent IAM resources separately and set it to `false`. |

The VCN and all spoke/on-premises networks must use distinct, non-overlapping
CIDRs. Confirm that the chosen floating HA IPs are neither allocated to another
resource nor inside OCI's reserved addresses for their subnet.

## Two spokes

For two spoke VCNs, put **one CIDR per spoke VCN** in `spoke_cidrs`. For
example, if spoke A is `10.9.0.0/24` and spoke B is `10.10.0.0/24`:

```hcl
spoke_cidrs = [
  "10.9.0.0/24",  # Spoke A VCN
  "10.10.0.0/24", # Spoke B VCN
]
```

Use every routed CIDR if a spoke contains multiple address ranges. The list
drives the routes created in the hub route tables and the FortiGate transit
ingress route table. Re-run `terraform plan` and `terraform apply` after
changing it.

Terraform creates the **hub** DRG attachment and the `RT-Spoke`, `RT-Hub`, and
`RT-OnPrem` DRG route tables. It does **not** create attachments for the spoke
VCNs. For each of the two spokes, complete the following in OCI (or manage the
same resources in separate Terraform code):

1. Attach the spoke VCN to the same DRG created/reused by this deployment.
2. Associate that spoke attachment with `RT-Spoke`. This makes its default DRG
   route send traffic to the hub VCN attachment for firewall inspection.
3. In each spoke workload subnet route table, add routes for the destinations
   that must be inspected—commonly `0.0.0.0/0`, or selected hub, other-spoke,
   and on-premises CIDRs—with the spoke's DRG attachment as the target.
4. Confirm the spoke VCN CIDR is advertised/imported by the DRG attachment.
   `Import-Hub` accepts VCN attachment routes, and `RT-Hub` is already attached
   to the hub VCN attachment by this configuration.
5. Permit the intended traffic in both spoke and hub security lists/NSGs and
   add matching FortiGate firewall policies and routes. A DRG route alone does
   not permit traffic through FortiGate.
6. Test both directions (spoke A ↔ spoke B, spoke ↔ hub, and spoke ↔ on-prem,
   if applicable), then perform a controlled HA failover test. Verify that the
   floating indoor/untrust IPs and shared public IP move as expected.

The intended inspected path is:

```text
Spoke A/B workload subnet → spoke DRG attachment → RT-Spoke
→ hub DRG attachment → VCN-Hub-Ingress → FortiGate floating indoor IP
→ FortiGate policy/routing → destination
```

Do not add a more-specific route that bypasses the DRG/FortiGate path unless
that bypass is deliberate and approved. Ensure routes are symmetric: return
traffic needs the same inspection path, especially for stateful FortiGate
policies.

## Deploy and verify

```bash
cd deploy-two-vms
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

After a successful apply, review `deployment_summary.txt` and `terraform
output`. The summary contains firewall management URLs, initial credentials,
and infrastructure identifiers, so treat it as sensitive operational data.

The initial FortiGate password reported by this configuration is the instance
OCID. Change it immediately after first login and finish the FortiGate HA and
OCI Fabric Connector configuration before carrying production traffic.
