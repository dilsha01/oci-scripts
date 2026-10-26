# =============================================================================
# network.tf – Subnet definitions for the FortiGate HA pair
#
# TODO: Replace every value marked with REPLACE_ before applying.
# =============================================================================

# ── Compartment for network resources ────────────────────────────────────────
# Using the same network_compartment resolved in main.tf (local.net_compartment)

# ── MGMT Subnet ───────────────────────────────────────────────────────────────
resource "oci_core_subnet" "mgmt" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-HUB-MGMT"
  cidr_block                 = "10.8.0.128/26"       # REPLACE_MGMT_CIDR  e.g. 10.50.1.64/26
  dns_label                  = "mgmt"
  prohibit_public_ip_on_vnic = false                # MGMT needs a public IP
  security_list_ids          = []                   # REPLACE_MGMT_SECURITY_LIST_OCIDS (optional)
  route_table_id             = null                 # REPLACE_MGMT_ROUTE_TABLE_OCID  (null = VCN default)

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# ── Indoor Subnet ─────────────────────────────────────────────────────────────
resource "oci_core_subnet" "indoor" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-INDOOR"
  cidr_block                 = "10.8.0.192/27"      # REPLACE_INDOOR_CIDR  e.g. 10.50.1.144/28
  dns_label                  = "indoor"
  prohibit_public_ip_on_vnic = true                 # private subnet
  security_list_ids          = []                   # REPLACE_INDOOR_SECURITY_LIST_OCIDS (optional)
  route_table_id             = null                 # REPLACE_INDOOR_ROUTE_TABLE_OCID

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# ── Untrust / DMZ Subnet ──────────────────────────────────────────────────────
resource "oci_core_subnet" "untrust" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-DMZ"
  cidr_block                 = "10.8.0.224/28"      # REPLACE_UNTRUST_CIDR  e.g. 10.50.1.128/28
  dns_label                  = "untrust"
  prohibit_public_ip_on_vnic = false                # untrust VNIC gets a public IP
  security_list_ids          = []                   # REPLACE_UNTRUST_SECURITY_LIST_OCIDS (optional)
  route_table_id             = null                 # REPLACE_UNTRUST_ROUTE_TABLE_OCID

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# ── Heartbeat Subnet ──────────────────────────────────────────────────────────
resource "oci_core_subnet" "heartbeat" {
  compartment_id             = local.net_compartment
  vcn_id                     = var.vcn_ocid
  display_name               = "PR-HEARTBEA"
  cidr_block                 = "10.8.0.240/28"      # REPLACE_HEARTBEAT_CIDR  e.g. 10.50.1.160/29
  dns_label                  = "heartbeat"
  prohibit_public_ip_on_vnic = true                 # private subnet
  security_list_ids          = []                   # REPLACE_HEARTBEAT_SECURITY_LIST_OCIDS (optional)
  route_table_id             = null                 # REPLACE_HEARTBEAT_ROUTE_TABLE_OCID

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "subnet_ids" {
  description = "OCIDs of the four FortiGate subnets"
  value = {
    mgmt      = oci_core_subnet.mgmt.id
    indoor    = oci_core_subnet.indoor.id
    untrust   = oci_core_subnet.untrust.id
    heartbeat = oci_core_subnet.heartbeat.id
  }
}
