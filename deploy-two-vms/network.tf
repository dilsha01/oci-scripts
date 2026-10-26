
# =============================================================================
# network.tf - Subnet definitions for the FortiGate HA pair
# Existing VCN; same-AD active-passive HA
# =============================================================================

# Network compartment is resolved in main.tf as local.net_compartment.

# -----------------------------------------------------------------------------
# Management subnet - port1
# -----------------------------------------------------------------------------
resource "oci_core_subnet" "mgmt" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-HUB-MGMT"
  cidr_block                 = "10.8.0.128/26"
  dns_label                  = "mgmt"
  prohibit_public_ip_on_vnic = false
  security_list_ids          = [data.oci_core_vcns.vcn.virtual_networks[0].default_security_list_id]
  route_table_id             = oci_core_route_table.mgmt.id

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags
    ]
  }
}

# -----------------------------------------------------------------------------
# Indoor / trust subnet - port2
# -----------------------------------------------------------------------------
resource "oci_core_subnet" "indoor" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-INDOOR"
  cidr_block                 = "10.8.0.192/27"
  dns_label                  = "indoor"
  prohibit_public_ip_on_vnic = true
  security_list_ids          = [data.oci_core_vcns.vcn.virtual_networks[0].default_security_list_id]
  route_table_id             = oci_core_route_table.indoor.id

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags
    ]
  }
}

# -----------------------------------------------------------------------------
# Untrust / DMZ subnet - port3
# -----------------------------------------------------------------------------
resource "oci_core_subnet" "untrust" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-DMZ"
  cidr_block                 = "10.8.0.224/28"
  dns_label                  = "untrust"
  prohibit_public_ip_on_vnic = false
  security_list_ids          = [data.oci_core_vcns.vcn.virtual_networks[0].default_security_list_id]
  route_table_id             = oci_core_route_table.untrust.id

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags
    ]
  }
}

# -----------------------------------------------------------------------------
# Heartbeat subnet - port4 (uses Default Route Table with 0 rules)
# -----------------------------------------------------------------------------
resource "oci_core_subnet" "heartbeat" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-HEARTBEAT"
  cidr_block                 = "10.8.0.240/28"
  dns_label                  = "heartbeat"
  prohibit_public_ip_on_vnic = true
  security_list_ids          = [data.oci_core_vcns.vcn.virtual_networks[0].default_security_list_id]
  route_table_id             = null

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags
    ]
  }
}

# -----------------------------------------------------------------------------
# OSN Services Lookup for Service Gateway
# -----------------------------------------------------------------------------
data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# =============================================================================
# Gateways (created automatically if OCID is not provided)
# =============================================================================

# 1. Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  count          = var.create_internet_gateway && var.internet_gateway_ocid == "" ? 1 : 0
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "internet-gateway"
  enabled        = true

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 2. NAT Gateway
resource "oci_core_nat_gateway" "nat" {
  count          = var.create_nat_gateway && var.nat_gateway_ocid == "" ? 1 : 0
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "NATGW-HUB"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 3. Service Gateway
resource "oci_core_service_gateway" "sgw" {
  count          = var.create_service_gateway && var.service_gateway_ocid == "" ? 1 : 0
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "SVGW-HUB"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 4. Dynamic Routing Gateway (DRG)
resource "oci_core_drg" "drg" {
  count          = var.create_drg && var.drg_ocid == "" ? 1 : 0
  compartment_id = local.net_compartment
  display_name   = "hub-drg"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Effective Gateway OCIDs & Plan-time Known Booleans
locals {
  has_drg            = var.drg_ocid != "" || var.create_drg
  has_igw            = var.internet_gateway_ocid != "" || var.create_internet_gateway
  has_nat            = var.nat_gateway_ocid != "" || var.create_nat_gateway
  has_sgw            = var.service_gateway_ocid != "" || var.create_service_gateway
  enable_drg_transit = local.has_drg && var.manage_drg_transit_routing

  effective_igw_id    = var.internet_gateway_ocid != "" ? var.internet_gateway_ocid : try(oci_core_internet_gateway.igw[0].id, "")
  effective_nat_id    = var.nat_gateway_ocid != "" ? var.nat_gateway_ocid : try(oci_core_nat_gateway.nat[0].id, "")
  effective_sgw_id    = var.service_gateway_ocid != "" ? var.service_gateway_ocid : try(oci_core_service_gateway.sgw[0].id, "")
  effective_drg_id    = var.drg_ocid != "" ? var.drg_ocid : try(oci_core_drg.drg[0].id, "")
  managed_spoke_cidrs = flatten([for spoke in values(var.spokes) : spoke.cidrs])
  all_spoke_cidrs     = distinct(concat(var.spoke_cidrs, local.managed_spoke_cidrs))
  all_target_cidrs    = distinct(concat(local.all_spoke_cidrs, var.onprem_cidrs))

  spoke_subnet_route_table_attachments = {
    for attachment in flatten([
      for spoke_key, spoke in var.spokes : [
        for subnet_id in spoke.workload_subnet_ids : {
          key       = "${spoke_key}/${subnet_id}"
          spoke_key = spoke_key
          subnet_id = subnet_id
        }
      ]
    ]) : attachment.key => attachment
  }
}

# =============================================================================
# DRG Transit Routing Configuration (OCI Transit Routing Architecture)
# =============================================================================

# DRG Route Table 1: RT-Spoke (forces all spoke-to-spoke/outbound traffic to Hub VCN)
resource "oci_core_drg_route_table" "rt_spoke" {
  count        = local.enable_drg_transit ? 1 : 0
  drg_id       = local.effective_drg_id
  display_name = "RT-Spoke"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# DRG Import Route Distribution: Import-Hub (imports routes from all VCN & On-Prem attachments)
resource "oci_core_drg_route_distribution" "import_hub" {
  count             = local.enable_drg_transit ? 1 : 0
  drg_id            = local.effective_drg_id
  distribution_type = "IMPORT"
  display_name      = "Import-Hub"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Statement 10: Import spoke VCN routes
resource "oci_core_drg_route_distribution_statement" "import_spokes" {
  count                     = local.enable_drg_transit ? 1 : 0
  drg_route_distribution_id = oci_core_drg_route_distribution.import_hub[0].id
  action                    = "ACCEPT"
  priority                  = 10

  match_criteria {
    match_type      = "DRG_ATTACHMENT_TYPE"
    attachment_type = "VCN"
  }
}

# Statement 20: Import On-Premises FastConnect virtual circuits
resource "oci_core_drg_route_distribution_statement" "import_virtual_circuits" {
  count                     = local.enable_drg_transit ? 1 : 0
  drg_route_distribution_id = oci_core_drg_route_distribution.import_hub[0].id
  action                    = "ACCEPT"
  priority                  = 20

  match_criteria {
    match_type      = "DRG_ATTACHMENT_TYPE"
    attachment_type = "VIRTUAL_CIRCUIT"
  }
}

# Statement 30: Import On-Premises IPSec VPN tunnels
resource "oci_core_drg_route_distribution_statement" "import_ipsec" {
  count                     = local.enable_drg_transit ? 1 : 0
  drg_route_distribution_id = oci_core_drg_route_distribution.import_hub[0].id
  action                    = "ACCEPT"
  priority                  = 30

  match_criteria {
    match_type      = "DRG_ATTACHMENT_TYPE"
    attachment_type = "IPSEC_TUNNEL"
  }
}

# DRG Route Table 2: RT-Hub (used by Hub VCN attachment, evaluates routes imported by Import-Hub)
resource "oci_core_drg_route_table" "rt_hub" {
  count                            = local.enable_drg_transit ? 1 : 0
  drg_id                           = local.effective_drg_id
  display_name                     = "RT-Hub"
  import_drg_route_distribution_id = oci_core_drg_route_distribution.import_hub[0].id

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# DRG Route Table 3: RT-OnPrem (used by on-prem attachments to steer inbound on-prem traffic to Hub VCN)
resource "oci_core_drg_route_table" "rt_onprem" {
  count        = local.enable_drg_transit ? 1 : 0
  drg_id       = local.effective_drg_id
  display_name = "RT-OnPrem"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Static route in RT-OnPrem for each Spoke CIDR + Hub CIDR pointing to the Hub VCN Attachment
resource "oci_core_drg_route_table_route_rule" "onprem_to_hub" {
  for_each                   = local.enable_drg_transit ? toset(concat(var.spoke_cidrs, [data.oci_core_vcns.vcn.virtual_networks[0].cidr_block])) : []
  drg_route_table_id         = oci_core_drg_route_table.rt_onprem[0].id
  destination                = each.value
  destination_type           = "CIDR_BLOCK"
  next_hop_drg_attachment_id = oci_core_drg_attachment.drg_attachment[0].id
}

# Hub VCN DRG Attachment: links DRG to VCN-Hub with Ingress inspection route table
resource "oci_core_drg_attachment" "drg_attachment" {
  count        = local.has_drg ? 1 : 0
  drg_id       = local.effective_drg_id
  display_name = "hub-drg-attachment"

  # Traffic entering DRG from Hub VCN uses RT-Hub (evaluates imported routes back to spokes)
  drg_route_table_id = try(oci_core_drg_route_table.rt_hub[0].id, null)

  network_details {
    id   = var.vcn_ocid
    type = "VCN"
    # Associates VCN Transit Ingress route table: steers all incoming traffic to FortiGate Indoor Private IP
    route_table_id = oci_core_route_table.ingress.id
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Spoke VCN attachments. Each attachment uses RT-Spoke so traffic entering the
# DRG from a spoke first goes to the hub VCN and FortiGate for inspection.
resource "oci_core_drg_attachment" "spoke" {
  for_each = local.enable_drg_transit ? var.spokes : {}

  drg_id             = local.effective_drg_id
  display_name       = "${each.key}-drg-attachment"
  drg_route_table_id = oci_core_drg_route_table.rt_spoke[0].id

  network_details {
    id   = each.value.vcn_id
    type = "VCN"
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Static default route (0.0.0.0/0) in RT-Spoke directing all spoke traffic into Hub VCN Attachment
resource "oci_core_drg_route_table_route_rule" "spoke_default_to_hub" {
  count                      = local.enable_drg_transit ? 1 : 0
  drg_route_table_id         = oci_core_drg_route_table.rt_spoke[0].id
  destination                = "0.0.0.0/0"
  destination_type           = "CIDR_BLOCK"
  next_hop_drg_attachment_id = oci_core_drg_attachment.drg_attachment[0].id
}

# A dedicated route table is created for each managed spoke. Associating it
# with the supplied workload subnets replaces their current route-table
# association, so include every required destination in route_cidrs.
resource "oci_core_route_table" "spoke_workload" {
  for_each = local.enable_drg_transit ? var.spokes : {}

  compartment_id = each.value.compartment_id
  vcn_id         = each.value.vcn_id
  display_name   = "${each.key}-workload-to-drg"

  dynamic "route_rules" {
    for_each = toset(each.value.route_cidrs)
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Inspected traffic from ${each.key} is routed through the DRG and FortiGate"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }

  depends_on = [oci_core_drg_attachment.spoke]
}

resource "oci_core_route_table_attachment" "spoke_workload" {
  for_each = local.enable_drg_transit ? local.spoke_subnet_route_table_attachments : {}

  subnet_id      = each.value.subnet_id
  route_table_id = oci_core_route_table.spoke_workload[each.value.spoke_key].id
}

# -----------------------------------------------------------------------------
# Route Tables matching production architecture
# -----------------------------------------------------------------------------

# 1. Management Subnet Route Table
resource "oci_core_route_table" "mgmt" {
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "mgmt-subnet-route-table"

  dynamic "route_rules" {
    for_each = local.has_igw ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_igw_id
      description       = "Traffic destined for networks outside the VCN is routed through the Internet Gateway"
    }
  }

  dynamic "route_rules" {
    for_each = local.has_drg ? local.all_target_cidrs : []
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Traffic destined for spoke/on-prem CIDR ${route_rules.value} is routed through the DRG"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 2. Indoor Subnet Route Table
resource "oci_core_route_table" "indoor" {
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "indoor-subnet-route-table"

  dynamic "route_rules" {
    for_each = local.has_drg ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Traffic destined for networks outside the VCN is routed through the DRG"
    }
  }

  dynamic "route_rules" {
    for_each = local.has_drg ? local.all_target_cidrs : []
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Traffic destined for spoke/on-prem CIDR ${route_rules.value} is routed through the DRG"
    }
  }

  dynamic "route_rules" {
    for_each = local.has_sgw ? [1] : []
    content {
      destination       = data.oci_core_services.all_services.services[0].cidr_block
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = local.effective_sgw_id
      description       = "Traffic destined for all OCI services in Oracle Services Network is routed through Service Gateway"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 3. Untrust / Outdoor Subnet Route Table
resource "oci_core_route_table" "untrust" {
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "outdoor-subnet-route-table"

  dynamic "route_rules" {
    for_each = (local.has_nat || local.has_igw) ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.has_nat ? local.effective_nat_id : local.effective_igw_id
      description       = "Default outbound traffic route"
    }
  }

  dynamic "route_rules" {
    for_each = local.has_sgw ? [1] : []
    content {
      destination       = data.oci_core_services.all_services.services[0].cidr_block
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = local.effective_sgw_id
      description       = "Traffic destined for all OCI services in Oracle Services Network is routed through the Service Gateway"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 4. Ingress Route Table (VCN-Hub-Ingress)
resource "oci_core_route_table" "ingress" {
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "VCN-Hub-Ingress"

  dynamic "route_rules" {
    for_each = local.all_target_cidrs
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = module.fw_vm_01.secondary_private_ip_ids["1"]
      description       = "Transit ingress route to FortiGate Indoor Private IP for inspection"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 5. Web / Workload Subnet Route Table
resource "oci_core_route_table" "web" {
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "web-subnet-route-table"

  dynamic "route_rules" {
    for_each = local.has_igw ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_igw_id
      description       = "Traffic destined for networks outside the VCN is routed through the Internet Gateway"
    }
  }

  dynamic "route_rules" {
    for_each = local.has_drg ? local.all_target_cidrs : []
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Traffic destined for spoke/on-prem CIDR ${route_rules.value} is routed through the DRG"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# 6. Hub VCN Ingress Route Table (Service Gateway Ingress)
resource "oci_core_route_table" "hub_ingress" {
  compartment_id = local.net_compartment
  vcn_id         = var.vcn_ocid
  display_name   = "hub-vcn-ingress-route-table"

  dynamic "route_rules" {
    for_each = local.has_sgw ? [1] : []
    content {
      destination       = data.oci_core_services.all_services.services[0].cidr_block
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = local.effective_sgw_id
      description       = "Traffic destined for all OCI services in Oracle Services Network is routed through Service Gateway"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "subnet_ids" {
  description = "OCIDs of the four FortiGate subnets"

  value = {
    mgmt      = oci_core_subnet.mgmt.id
    indoor    = oci_core_subnet.indoor.id
    untrust   = oci_core_subnet.untrust.id
    heartbeat = oci_core_subnet.heartbeat.id
  }
}

output "route_table_ids" {
  description = "OCIDs of the created route tables"

  value = {
    mgmt        = oci_core_route_table.mgmt.id
    indoor      = oci_core_route_table.indoor.id
    untrust     = oci_core_route_table.untrust.id
    ingress     = oci_core_route_table.ingress.id
    web         = oci_core_route_table.web.id
    hub_ingress = oci_core_route_table.hub_ingress.id
  }
}

output "drg_transit_routing" {
  description = "OCIDs of the DRG Transit Route Tables and Distributions"

  value = {
    rt_spoke           = try(oci_core_drg_route_table.rt_spoke[0].id, null)
    rt_hub             = try(oci_core_drg_route_table.rt_hub[0].id, null)
    rt_onprem          = try(oci_core_drg_route_table.rt_onprem[0].id, null)
    import_hub         = try(oci_core_drg_route_distribution.import_hub[0].id, null)
    hub_drg_attachment = try(oci_core_drg_attachment.drg_attachment[0].id, null)
  }
}

output "spoke_drg_attachment_ids" {
  description = "DRG attachment OCIDs created for managed spoke VCNs"
  value       = { for name, attachment in oci_core_drg_attachment.spoke : name => attachment.id }
}

output "spoke_workload_route_table_ids" {
  description = "Route table OCIDs associated with managed spoke workload subnets"
  value       = { for name, route_table in oci_core_route_table.spoke_workload : name => route_table.id }
}

output "gateway_ids" {
  description = "OCIDs of the gateways used or created"

  value = {
    internet_gateway = local.effective_igw_id
    nat_gateway      = local.effective_nat_id
    service_gateway  = local.effective_sgw_id
    drg              = local.effective_drg_id
  }
}


