terraform {
  required_version = ">= 1.3.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.2.0"
    }
  }
}

# ---------------- Variables ----------------
variable "region" {
  description = "Your OCI region identifier, e.g. ap-singapore-1"
  type        = string
}
variable "tenancy_ocid" { type = string }
variable "compartment_ocid" {
  description = "OCID of compartment bwg-ebs-network"
  type        = string
}
variable "network_compartment_ocid" {
  description = "Compartment of the existing VCN/subnet. Leave empty if same as compartment_ocid"
  type        = string
  default     = ""
}

# Basic info
variable "instance_name" {
  type    = string
  default = "instance-20261023-1134"
}
variable "ad_index" {
  description = "0 = AD-1, 1 = AD-2, 2 = AD-3"
  type        = number
  default     = 0
}

# Shape
variable "shape" {
  type    = string
  default = "VM.Standard.E4.Flex"
}
variable "ocpus" {
  type    = number
  default = 4
}
variable "memory_in_gbs" {
  type    = number
  default = 16
}

# Image selection
variable "image_source" {
  description = "marketplace | platform | custom"
  type        = string
  default     = "marketplace"
  validation {
    condition     = contains(["marketplace", "platform", "custom"], var.image_source)
    error_message = "image_source must be marketplace, platform or custom."
  }
}
variable "marketplace_listing_name" {
  type    = string
  default = "FortiGate Next-Gen Firewall (BYOL)"
}
variable "marketplace_listing_id" {
  description = "Optional listing OCID, overrides the name lookup"
  type        = string
  default     = ""
}
variable "marketplace_package_version" {
  type    = string
  default = "8.0.1"
}
variable "accept_marketplace_terms" {
  description = "Set false if you already accepted the terms manually in the console"
  type        = bool
  default     = true
}
variable "platform_os" {
  type    = string
  default = "Oracle Linux"
}
variable "platform_os_version" {
  type    = string
  default = "8"
}
variable "custom_image_ocid" {
  type    = string
  default = ""
}

# Networking (existing)
variable "vcn_name" {
  type    = string
  default = "Test-VCN"
}
variable "subnet_name" {
  type    = string
  default = "public subnet-Test-VCN"
}
variable "vnic_name" {
  type    = string
  default = "vnic01"
}
variable "private_ip" {
  description = "Must be free and inside the subnet CIDR"
  type        = string
  default     = "10.0.0.244"
}
variable "hostname_label" {
  description = "DNS hostname (subnet must have a DNS label). Empty = none"
  type        = string
  default     = ""
}

# Storage
variable "boot_volume_size_gb" {
  type    = number
  default = 50
}
variable "boot_volume_vpus_per_gb" {
  type    = number
  default = 10
}

# SSH key: leave empty to generate a key pair (like "Generate key pair" in the console)
variable "ssh_public_key" {
  type    = string
  default = ""
}

# Auth comes from ~/.oci/config (DEFAULT profile)
provider "oci" {
  region = var.region
}

# ---------------- SSH key ----------------
resource "tls_private_key" "ssh" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  filename        = "${path.module}/${var.instance_name}.key"
  content         = tls_private_key.ssh[0].private_key_pem
  file_permission = "0600"
}

resource "local_file" "public_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  filename        = "${path.module}/${var.instance_name}.key.pub"
  content         = tls_private_key.ssh[0].public_key_openssh
  file_permission = "0644"
}

locals {
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh[0].public_key_openssh
  net_compartment = var.network_compartment_ocid != "" ? var.network_compartment_ocid : var.compartment_ocid
}

# ---------------- Lookups ----------------
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_vcns" "vcn" {
  compartment_id = local.net_compartment
  display_name   = var.vcn_name
}

data "oci_core_subnets" "subnet" {
  compartment_id = local.net_compartment
  vcn_id         = data.oci_core_vcns.vcn.virtual_networks[0].id
  display_name   = var.subnet_name
}

data "oci_core_images" "platform" {
  count                    = var.image_source == "platform" ? 1 : 0
  compartment_id           = var.compartment_ocid
  operating_system         = var.platform_os
  operating_system_version = var.platform_os_version
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ---------------- Marketplace image ----------------
locals {
  use_mp        = var.image_source == "marketplace"
  accept_terms  = local.use_mp && var.accept_marketplace_terms
  mp_listing_id = var.marketplace_listing_id != "" ? var.marketplace_listing_id : try(data.oci_marketplace_listings.by_name[0].listings[0].id, "")
}

data "oci_marketplace_listings" "by_name" {
  count          = local.use_mp && var.marketplace_listing_id == "" ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = [var.marketplace_listing_name]
}

data "oci_marketplace_listing_packages" "all" {
  count          = local.use_mp ? 1 : 0
  listing_id     = local.mp_listing_id
  compartment_id = var.compartment_ocid
}

data "oci_marketplace_listing_package" "pkg" {
  count           = local.use_mp ? 1 : 0
  listing_id      = local.mp_listing_id
  package_version = var.marketplace_package_version
  compartment_id  = var.compartment_ocid
}

data "oci_marketplace_listing_package_agreements" "agr" {
  count           = local.accept_terms ? 1 : 0
  listing_id      = local.mp_listing_id
  package_version = var.marketplace_package_version
  compartment_id  = var.compartment_ocid
}
resource "oci_marketplace_listing_package_agreement" "agr" {
  count           = local.accept_terms ? 1 : 0
  agreement_id    = data.oci_marketplace_listing_package_agreements.agr[0].agreements[0].id
  listing_id      = local.mp_listing_id
  package_version = var.marketplace_package_version
  compartment_id  = var.compartment_ocid
}

resource "oci_marketplace_accepted_agreement" "agr" {
  count           = local.accept_terms ? 1 : 0
  agreement_id    = data.oci_marketplace_listing_package_agreements.agr[0].agreements[0].id
  compartment_id  = var.compartment_ocid
  listing_id      = local.mp_listing_id
  package_version = var.marketplace_package_version
  signature       = oci_marketplace_listing_package_agreement.agr[0].signature
}

data "oci_core_app_catalog_listing_resource_version" "rv" {
  count            = local.use_mp ? 1 : 0
  listing_id       = data.oci_marketplace_listing_package.pkg[0].app_catalog_listing_id
  resource_version = data.oci_marketplace_listing_package.pkg[0].app_catalog_listing_resource_version
}

resource "oci_core_app_catalog_listing_resource_version_agreement" "agr" {
  count                    = local.accept_terms ? 1 : 0
  listing_id               = data.oci_marketplace_listing_package.pkg[0].app_catalog_listing_id
  listing_resource_version = data.oci_marketplace_listing_package.pkg[0].app_catalog_listing_resource_version
}

resource "oci_core_app_catalog_subscription" "sub" {
  count                    = local.accept_terms ? 1 : 0
  compartment_id           = var.compartment_ocid
  listing_id               = data.oci_marketplace_listing_package.pkg[0].app_catalog_listing_id
  listing_resource_version = data.oci_marketplace_listing_package.pkg[0].app_catalog_listing_resource_version
  eula_link                = oci_core_app_catalog_listing_resource_version_agreement.agr[0].eula_link
  oracle_terms_of_use_link = oci_core_app_catalog_listing_resource_version_agreement.agr[0].oracle_terms_of_use_link
  signature                = oci_core_app_catalog_listing_resource_version_agreement.agr[0].signature
  time_retrieved           = oci_core_app_catalog_listing_resource_version_agreement.agr[0].time_retrieved
  depends_on               = [oci_marketplace_accepted_agreement.agr]
}

locals {
  image_id = (
    var.image_source == "custom" ? var.custom_image_ocid :
    var.image_source == "platform" ? data.oci_core_images.platform[0].images[0].id :
    data.oci_core_app_catalog_listing_resource_version.rv[0].listing_resource_id
  )
}

# ---------------- VM ----------------
resource "oci_core_instance" "vm" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.ad_index].name
  display_name        = var.instance_name
  shape               = var.shape
  # Fault domain: not set -> Oracle chooses. Capacity type: on-demand (default).

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
    # burstable = no -> baseline_ocpu_utilization not set
  }

  # Shielded instance, SMT enabled, secure/measured boot, TPM, confidential computing all off
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
    source_id               = local.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
    boot_volume_vpus_per_gb = var.boot_volume_vpus_per_gb
  }

  is_pv_encryption_in_transit_enabled = false

  create_vnic_details {
    display_name              = var.vnic_name
    subnet_id                 = data.oci_core_subnets.subnet.subnets[0].id
    assign_public_ip          = true
    private_ip                = var.private_ip
    assign_private_dns_record = true
    hostname_label            = var.hostname_label != "" ? var.hostname_label : null
    # no network security groups
  }

  # Authorization header required (IMDSv2 only)
  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  # Live migration: Oracle chooses (not set). Restore state after maintenance: yes
  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    # no initialization script
  }

  depends_on = [oci_core_app_catalog_subscription.sub]
}

# ---------------- Outputs ----------------
output "vm_public_ip" {
  value = oci_core_instance.vm.public_ip
}
output "vm_private_ip" {
  value = oci_core_instance.vm.private_ip
}
output "login" {
  value = "https://${oci_core_instance.vm.public_ip}  (user: admin, initial password: instance OCID)"
}
output "marketplace_available_versions" {
  value = local.use_mp ? [for p in data.oci_marketplace_listing_packages.all[0].listing_packages : p.package_version] : []
}
output "selected_image_id" {
  value = local.image_id
}