# FortiGate HA Hub with OCI DRG Transit Routing

This Terraform configuration creates an active/passive FortiGate HA pair in an
existing OCI hub VCN. It creates the four firewall subnets, route tables,
optional gateways, a hub VCN DRG attachment, and (optionally) the IAM resources
needed by the FortiGate OCI Fabric Connector to move the floating IPs during a
failover.

It is intentionally **not** a complete landing-zone deployment: the hub VCN,
spoke VCNs, and their workload subnets must already exist. When configured in
the `spokes` input, Terraform creates the spoke DRG attachments and workload
subnet route tables. Security rules and FortiGate policies remain your
responsibility.

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

For two spoke VCNs, use the `spokes` map. Terraform will create each spoke
attachment, associate it with `RT-Spoke`, create a dedicated route table, and
attach that route table to every workload subnet you list. For example:

```hcl
spokes = {
  spoke_a = {
    compartment_id      = "ocid1.compartment.oc1..SPOKE_A_COMPARTMENT_OCID"
    vcn_id              = "ocid1.vcn.oc1.ap-hyderabad-1.SPOKE_A_VCN_OCID"
    cidrs               = ["10.9.0.0/24"]
    workload_subnet_ids = ["ocid1.subnet.oc1.ap-hyderabad-1.SPOKE_A_SUBNET_OCID"]
    route_cidrs         = ["0.0.0.0/0"]
  }
  spoke_b = {
    compartment_id      = "ocid1.compartment.oc1..SPOKE_B_COMPARTMENT_OCID"
    vcn_id              = "ocid1.vcn.oc1.ap-hyderabad-1.SPOKE_B_VCN_OCID"
    cidrs               = ["10.10.0.0/24"]
    workload_subnet_ids = ["ocid1.subnet.oc1.ap-hyderabad-1.SPOKE_B_SUBNET_OCID"]
    route_cidrs         = ["0.0.0.0/0"]
  }
}
```

Use every routed VCN CIDR in `cidrs`. `route_cidrs` defaults to `0.0.0.0/0`,
which makes all workload-subnet traffic use the inspection path. Supply a
smaller list instead if only selected destinations require inspection. The
configured CIDRs drive the hub return routes and the FortiGate transit ingress
route table. Re-run `terraform plan` and `terraform apply` after changing it.

Each managed spoke VCN must not already have a DRG attachment. If it does,
import that attachment into the matching `oci_core_drg_attachment.spoke` state
address before applying, or remove it from `spokes` and manage the association
outside this configuration. A VCN can be attached to only one DRG.

Terraform creates the hub DRG attachment plus `RT-Spoke`, `RT-Hub`, and
`RT-OnPrem`. With `spokes` populated, it also completes the first three items
below for each spoke:

1. Terraform attaches the spoke VCN to the same DRG and applies `RT-Spoke`.
2. Terraform creates a dedicated route table and attaches it to the supplied
   `workload_subnet_ids`. This **replaces** each subnet's current route-table
   association. Put all required routes in `route_cidrs`; do not use this on a
   subnet that needs unmanaged routes retained.
3. Terraform routes each `route_cidrs` destination to the DRG; `0.0.0.0/0` is
   the default inspection route.
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
