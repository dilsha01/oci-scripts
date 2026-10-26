terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ── Primary instance (VNIC[0] = MGMT) ────────────────────────────────────────
resource "oci_core_instance" "vm" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  fault_domain        = var.fault_domain
  display_name        = var.name
  shape               = var.shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  platform_config {
    type                                 = "AMD_VM"
    is_symmetric_multi_threading_enabled = true
    is_secure_boot_enabled               = false
    is_measured_boot_enabled             = false
    is_trusted_platform_module_enabled   = false
    is_memory_encryption_enabled         = false
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
    boot_volume_vpus_per_gb = var.boot_volume_vpus_per_gb
  }

  is_pv_encryption_in_transit_enabled = false

  create_vnic_details {
    display_name              = var.vnics[0].name
    hostname_label            = var.vnics[0].hostname_label
    subnet_id                 = var.vnics[0].subnet_id
    private_ip                = var.vnics[0].private_ip
    assign_public_ip          = false   # we manage public IPs ourselves below
    assign_private_dns_record = true
    skip_source_dest_check    = var.vnics[0].skip_source_dest_check
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

# ── Secondary VNICs (index 1-3) ───────────────────────────────────────────────
resource "oci_core_vnic_attachment" "secondary" {
  for_each = {
    for index, vnic in var.vnics :
    tostring(index) => vnic if index > 0
  }

  instance_id  = oci_core_instance.vm.id
  display_name = each.value.name

  create_vnic_details {
    display_name              = each.value.name
    hostname_label            = each.value.hostname_label
    subnet_id                 = each.value.subnet_id
    private_ip                = each.value.private_ip
    assign_public_ip          = false
    assign_private_dns_record = true
    skip_source_dest_check    = each.value.skip_source_dest_check
  }
}

# ── Secondary private IPs ─────────────────────────────────────────────────────
# For each VNIC that has secondary_private_ip set, resolve its VNIC OCID then
# create an extra private IP on it.

locals {
  secondary_ip_vnics = {
    for index, vnic in var.vnics :
    tostring(index) => vnic
    if vnic.secondary_private_ip != null
  }
}

# Look up the VNIC OCID for each secondary-IP candidate.
# For the primary VNIC (index == "0") the instance data source gives the VNIC id;
# for secondary attachments we use the attachment data source.
data "oci_core_vnic_attachments" "for_secondary_ip" {
  for_each       = local.secondary_ip_vnics
  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.vm.id

  depends_on = [oci_core_vnic_attachment.secondary]
}

resource "oci_core_private_ip" "secondary" {
  for_each = local.secondary_ip_vnics

  vnic_id = each.key == "0" ? (
    # Primary VNIC: resolve via vnic_attachments filtered by display_name
    [for a in data.oci_core_vnic_attachments.for_secondary_ip[each.key].vnic_attachments :
      a.vnic_id if a.display_name == each.value.name
    ][0]
  ) : (
    [for a in data.oci_core_vnic_attachments.for_secondary_ip[each.key].vnic_attachments :
      a.vnic_id if a.display_name == each.value.name
    ][0]
  )

  ip_address   = each.value.secondary_private_ip
  display_name = "${each.value.name}-secondary-ip"
}

# ── Reserved public IPs ───────────────────────────────────────────────────────
# For each VNIC with assign_public_ip = true:
#   1. Look up the oci_core_private_ip OCID for that VNIC's primary private IP
#   2. Create a RESERVED public IP and attach it to that private IP OCID

locals {
  public_ip_vnics = {
    for index, vnic in var.vnics :
    tostring(index) => vnic
    if vnic.assign_public_ip == true
  }
}

# Resolve the private IP OCID by IP address + subnet
data "oci_core_private_ips" "for_public_ip" {
  for_each   = local.public_ip_vnics
  ip_address = each.value.private_ip
  subnet_id  = each.value.subnet_id

  depends_on = [
    oci_core_instance.vm,
    oci_core_vnic_attachment.secondary,
  ]
}

# Create and attach the reserved public IP
resource "oci_core_public_ip" "reserved" {
  for_each = local.public_ip_vnics

  compartment_id = var.compartment_id
  lifetime       = "RESERVED"
  display_name   = "${var.name}-${each.value.name}-pub-ip"

  private_ip_id = data.oci_core_private_ips.for_public_ip[each.key].private_ips[0].id
}