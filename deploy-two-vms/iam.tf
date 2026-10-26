# =============================================================================
# iam.tf - Dynamic Group and IAM Policies for FortiGate HA Failover in OCI
# =============================================================================

# -----------------------------------------------------------------------------
# Dynamic Group for FortiGate VM instances
# Matches FW01 and FW02 so the instances can authenticate to OCI APIs
# (Instance Principal authentication for OCI Fabric Connector)
# -----------------------------------------------------------------------------
resource "oci_identity_dynamic_group" "fgt_ha" {
  count          = var.create_iam_resources ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = var.dynamic_group_name
  description    = "Dynamic group for FortiGate HA instances to manage floating secondary IPs and route tables"

  # Matches both FortiGate instances by their OCIDs
  matching_rule = "Any {instance.id = '${module.fw_vm_01.id}', instance.id = '${module.fw_vm_02.id}'}"

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# -----------------------------------------------------------------------------
# IAM Policy for FortiGate HA
# Grants the dynamic group permissions to move private IPs, manage public IPs,
# and update route tables during HA failover events.
# -----------------------------------------------------------------------------
locals {
  granular_iam_statements = [
    "Allow dynamic-group ${var.dynamic_group_name} to read compartments in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to read instances in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to read vnic-attachments in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to read subnets in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to manage private-ips in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to manage public-ips in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to manage route-tables in tenancy"
  ]

  simpler_iam_statements = [
    "Allow dynamic-group ${var.dynamic_group_name} to read compartments in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to read instances in tenancy",
    "Allow dynamic-group ${var.dynamic_group_name} to manage virtual-network-family in tenancy"
  ]
}

resource "oci_identity_policy" "fgt_ha" {
  count          = var.create_iam_resources ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = var.policy_name
  description    = "Policy allowing FortiGate HA dynamic group to manage secondary IPs, public IPs, and route tables"

  statements = var.use_granular_iam_policy ? local.granular_iam_statements : local.simpler_iam_statements

  depends_on = [oci_identity_dynamic_group.fgt_ha]

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "fgt_ha_dynamic_group_id" {
  description = "OCID of the FortiGate HA dynamic group"
  value       = try(oci_identity_dynamic_group.fgt_ha[0].id, null)
}

output "fgt_ha_policy_id" {
  description = "OCID of the FortiGate HA IAM policy"
  value       = try(oci_identity_policy.fgt_ha[0].id, null)
}
