
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
  route_table_id             = null

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
  route_table_id             = null

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
  route_table_id             = null

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags
    ]
  }
}

# -----------------------------------------------------------------------------
# Heartbeat subnet - port4
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
