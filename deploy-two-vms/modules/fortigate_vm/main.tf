terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

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
    display_name              = var.vnic_name
    hostname_label            = var.hostname_label
    subnet_id                 = var.subnet_id
    assign_public_ip          = true
    private_ip                = var.private_ip
    assign_private_dns_record = true
    skip_source_dest_check = true
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