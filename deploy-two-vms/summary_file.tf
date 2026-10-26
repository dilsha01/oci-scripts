# =============================================================================
# summary_file.tf - Automatically saves full deployment details to a text file
# on every 'terraform apply'
# =============================================================================

resource "local_file" "deployment_summary" {
  filename        = "${path.module}/deployment_summary.txt"
  file_permission = "0644"

  content = <<-EOT
================================================================================
           FORTIGATE ACTIVE-PASSIVE HA & OCI TRANSIT ROUTING DEPLOYMENT
================================================================================
Region          : ${var.region}
VCN Name        : ${var.vcn_name}
VCN OCID        : ${var.vcn_ocid}

--------------------------------------------------------------------------------
1. FIREWALL WEB GUI & SSH ACCESS CREDENTIALS
--------------------------------------------------------------------------------
FW01 (Primary Active):
  URL           : https://${module.fw_vm_01.public_ip}
  Username      : admin
  Initial Pwd   : ${module.fw_vm_01.id}
  MGMT Priv IP  : ${module.fw_vm_01.private_ip}
  MGMT Pub IP   : ${module.fw_vm_01.public_ip}

FW02 (Secondary Passive):
  URL           : https://${module.fw_vm_02.public_ip}
  Username      : admin
  Initial Pwd   : ${module.fw_vm_02.id}
  MGMT Priv IP  : ${module.fw_vm_02.private_ip}
  MGMT Pub IP   : ${module.fw_vm_02.public_ip}

--------------------------------------------------------------------------------
2. FLOATING HA & SHARED TRAFFIC IPS
--------------------------------------------------------------------------------
Shared Traffic Public IP (VIP) : ${oci_core_public_ip.shared_traffic.ip_address}
Untrust HA Movable IP (Port 3) : ${var.fw01_untrust_ha_ip} (Attached to FW01 port3)
Indoor HA Movable IP  (Port 2) : ${var.fw01_indoor_ha_ip} (Gateway for spokes)

--------------------------------------------------------------------------------
3. SUBNETS
--------------------------------------------------------------------------------
MGMT Subnet (port1)      : 10.8.0.128/26  [PR-HUB-MGMT]
  OCID                   : ${oci_core_subnet.mgmt.id}
  Route Table Attached   : mgmt-subnet-route-table

Indoor / Trust (port2)   : 10.8.0.192/27  [PR-INDOOR]
  OCID                   : ${oci_core_subnet.indoor.id}
  Route Table Attached   : indoor-subnet-route-table

Untrust / DMZ (port3)    : 10.8.0.224/28  [PR-DMZ]
  OCID                   : ${oci_core_subnet.untrust.id}
  Route Table Attached   : outdoor-subnet-route-table

Heartbeat (port4)        : 10.8.0.240/28  [PR-HEARTBEA]
  OCID                   : ${oci_core_subnet.heartbeat.id}
  Route Table Attached   : Default Route Table for VCN (intra-subnet only)

--------------------------------------------------------------------------------
4. GATEWAYS
--------------------------------------------------------------------------------
Dynamic Routing Gateway (DRG) : ${local.effective_drg_id}
Internet Gateway (IGW)        : ${local.effective_igw_id}
NAT Gateway (NATGW)           : ${local.effective_nat_id}
Service Gateway (SGW)         : ${local.effective_sgw_id}

--------------------------------------------------------------------------------
5. VCN ROUTE TABLES
--------------------------------------------------------------------------------
VCN-Hub-Ingress (Transit Ingress)
  OCID   : ${oci_core_route_table.ingress.id}

indoor-subnet-route-table
  OCID   : ${oci_core_route_table.indoor.id}

mgmt-subnet-route-table
  OCID   : ${oci_core_route_table.mgmt.id}

outdoor-subnet-route-table
  OCID   : ${oci_core_route_table.untrust.id}

web-subnet-route-table
  OCID   : ${oci_core_route_table.web.id}

hub-vcn-ingress-route-table
  OCID   : ${oci_core_route_table.hub_ingress.id}

--------------------------------------------------------------------------------
6. DRG CENTRAL TRANSIT ROUTING ARCHITECTURE
--------------------------------------------------------------------------------
Hub DRG Attachment    : ${try(oci_core_drg_attachment.drg_attachment[0].id, "N/A")}
RT-Spoke              : ${try(oci_core_drg_route_table.rt_spoke[0].id, "N/A")}
RT-Hub                : ${try(oci_core_drg_route_table.rt_hub[0].id, "N/A")}
RT-OnPrem             : ${try(oci_core_drg_route_table.rt_onprem[0].id, "N/A")}
Import-Hub            : ${try(oci_core_drg_route_distribution.import_hub[0].id, "N/A")}

--------------------------------------------------------------------------------
7. IAM ROLES & POLICIES
--------------------------------------------------------------------------------
Dynamic Group         : ${try(oci_identity_dynamic_group.fgt_ha[0].name, "N/A")} (${try(oci_identity_dynamic_group.fgt_ha[0].id, "N/A")})
IAM Policy            : ${try(oci_identity_policy.fgt_ha[0].name, "N/A")} (${try(oci_identity_policy.fgt_ha[0].id, "N/A")})
================================================================================
EOT
}
