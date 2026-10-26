
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
  display_name               = "PR-HEARTBEA"
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

resource "oci_core_drg_attachment" "drg_attachment" {
  count        = var.create_drg && var.drg_ocid == "" ? 1 : 0
  drg_id       = oci_core_drg.drg[0].id
  display_name = "hub-drg-attachment"

  network_details {
    id   = var.vcn_ocid
    type = "VCN"
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Effective Gateway OCIDs (prefers user-provided OCID, falls back to newly created gateway)
locals {
  effective_igw_id = var.internet_gateway_ocid != "" ? var.internet_gateway_ocid : try(oci_core_internet_gateway.igw[0].id, "")
  effective_nat_id = var.nat_gateway_ocid != "" ? var.nat_gateway_ocid : try(oci_core_nat_gateway.nat[0].id, "")
  effective_sgw_id = var.service_gateway_ocid != "" ? var.service_gateway_ocid : try(oci_core_service_gateway.sgw[0].id, "")
  effective_drg_id = var.drg_ocid != "" ? var.drg_ocid : try(oci_core_drg.drg[0].id, "")
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
    for_each = local.effective_igw_id != "" ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_igw_id
      description       = "Traffic destined for networks outside the VCN is routed through the Internet Gateway"
    }
  }

  dynamic "route_rules" {
    for_each = local.effective_drg_id != "" ? var.spoke_cidrs : []
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Traffic destined for spoke CIDR ${route_rules.value} is routed through the DRG"
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
    for_each = local.effective_drg_id != "" ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Traffic destined for networks outside the VCN is routed through the DRG"
    }
  }

  dynamic "route_rules" {
    for_each = local.effective_drg_id != "" ? var.spoke_cidrs : []
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = local.effective_drg_id
      description       = "Traffic destined for spoke CIDR ${route_rules.value} is routed through the DRG"
    }
  }

  dynamic "route_rules" {
    for_each = local.effective_sgw_id != "" ? [1] : []
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
    for_each = local.effective_nat_id != "" ? [local.effective_nat_id] : (local.effective_igw_id != "" ? [local.effective_igw_id] : [])
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = route_rules.value
      description       = "Default outbound traffic route"
    }
  }

  dynamic "route_rules" {
    for_each = local.effective_sgw_id != "" ? [1] : []
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
    for_each = var.spoke_cidrs
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
    mgmt    = oci_core_route_table.mgmt.id
    indoor  = oci_core_route_table.indoor.id
    untrust = oci_core_route_table.untrust.id
    ingress = oci_core_route_table.ingress.id
  }
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




