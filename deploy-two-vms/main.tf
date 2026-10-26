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
  type = string
}
variable "tenancy_ocid" { type = string }
variable "compartment_ocid" { type = string }
variable "network_compartment_ocid" {
  description = "Compartment of the existing VCN/subnet. Empty = same as compartment_ocid"
  type        = string
  default     = ""
}

variable "ad_index" {
  description = "0 = AD-1, 1 = AD-2, 2 = AD-3 (both VMs use the same AD)"
  type        = number
  default     = 0
}

# Shape (shared by both VMs)
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
variable "boot_volume_size_gb" {
  type    = number
  default = 50
}
variable "boot_volume_vpus_per_gb" {
  type    = number
  default = 10
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
  type    = string
  default = ""
}
variable "marketplace_package_version" {
  type    = string
  default = "8.0.1_(_X64_)"
}
variable "accept_marketplace_terms" {
  description = "Set false if the terms are already accepted"
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

# Existing network
variable "vcn_name" {
  type    = string
  default = "Test-VCN"
}
variable "subnet_name" {
  type    = string
  default = "public subnet-Test-VCN"
}

# VCN OCID – used for subnet creation in network.tf
variable "vcn_ocid" {
  description = "OCID of the existing VCN where subnets will be created"
  type        = string
  default     = "ocid1.vcn.oc1.ap-hyderabad-1.REPLACE_WITH_YOUR_VCN_OCID"
}

# SSH key: empty = generate one key pair shared by both VMs
variable "ssh_public_key" {
  type    = string
  default = ""
}
variable "ssh_key_name" {
  description = "File name used for the generated key"
  type        = string
  default     = "TestFW-VM01"
}


variable "fw01_indoor_ha_ip" {
  description = "Movable secondary IP on FW01 indoor/trust VNIC"
  type        = string
}

variable "fw01_untrust_ha_ip" {
  description = "Movable secondary IP on FW01 untrust VNIC"
  type        = string
}

variable "webapp_subnet_cidr" {
  description = "Approved CIDR for the protected workload subnet"
  type        = string
  default     = null
}

variable "internet_gateway_ocid" {
  description = "OCID of existing Internet Gateway for management / outbound routing"
  type        = string
  default     = ""
}

variable "drg_ocid" {
  description = "OCID of existing Dynamic Routing Gateway (DRG) for spoke and on-prem routing"
  type        = string
  default     = ""
}

variable "nat_gateway_ocid" {
  description = "OCID of existing NAT Gateway for untrust / outbound routing"
  type        = string
  default     = ""
}

variable "service_gateway_ocid" {
  description = "OCID of existing Service Gateway for Oracle Services Network"
  type        = string
  default     = ""
}

variable "create_internet_gateway" {
  description = "Whether to automatically create an Internet Gateway if internet_gateway_ocid is empty"
  type        = bool
  default     = true
}

variable "create_nat_gateway" {
  description = "Whether to automatically create a NAT Gateway if nat_gateway_ocid is empty"
  type        = bool
  default     = true
}

variable "create_service_gateway" {
  description = "Whether to automatically create a Service Gateway if service_gateway_ocid is empty"
  type        = bool
  default     = true
}

variable "create_drg" {
  description = "Whether to automatically create a Dynamic Routing Gateway (DRG) if drg_ocid is empty"
  type        = bool
  default     = true
}

variable "spoke_cidrs" {
  description = "List of Spoke CIDR blocks (e.g. ['10.50.2.0/25', '10.50.2.128/25']) routed via DRG and FortiGate"
  type        = list(string)
  default     = []
}


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
  filename        = "${path.module}/${var.ssh_key_name}.key"
  content         = tls_private_key.ssh[0].private_key_pem
  file_permission = "0600"
}

resource "local_file" "public_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  filename        = "${path.module}/${var.ssh_key_name}.key.pub"
  content         = tls_private_key.ssh[0].public_key_openssh
  file_permission = "0644"
}

locals {
  ssh_public_key  = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh[0].public_key_openssh
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

  ad_name   = data.oci_identity_availability_domains.ads.availability_domains[var.ad_index].name
  subnet_id = data.oci_core_subnets.subnet.subnets[0].id
}

# ---------------- VMs (same module, called twice) ----------------

# Keeps your already-created VM instead of destroying it
moved {
  from = oci_core_instance.vm
  to   = module.fw_vm_01.oci_core_instance.vm
}

module "fw_vm_01" {
  source = "./modules/fortigate_vm"

  name                = "FW01-VM"
  compartment_id      = var.compartment_ocid
  availability_domain = local.ad_name
  image_id            = local.image_id
  ssh_public_key      = local.ssh_public_key

  shape                   = var.shape
  ocpus                   = var.ocpus
  memory_in_gbs           = var.memory_in_gbs
  boot_volume_size_gb     = var.boot_volume_size_gb
  boot_volume_vpus_per_gb = var.boot_volume_vpus_per_gb

  # VNICs: [0] MGMT  [1] Indoor  [2] Untrust  [3] Heartbeat
  
vnics = [
  {
    # port1: management, with a dedicated public IP
    name                   = "FW01-MGMT"
    hostname_label         = "fw01-mgmt"
    subnet_id              = oci_core_subnet.mgmt.id
    private_ip             = "10.8.0.132"
    secondary_private_ip   = null
    assign_public_ip       = true
    skip_source_dest_check = false
  },
  {
    # port2: indoor/trust, with a movable secondary IP
    name                   = "FW01-INDOOR"
    hostname_label         = "fw01-indoor"
    subnet_id              = oci_core_subnet.indoor.id
    private_ip             = "10.8.0.196"
    secondary_private_ip   = var.fw01_indoor_ha_ip
    assign_public_ip       = false
    skip_source_dest_check = true
  },
  {
    # port3: untrust, with a movable secondary IP
    name                   = "FW01-UNTRUST"
    hostname_label         = "fw01-untrust"
    subnet_id              = oci_core_subnet.untrust.id
    private_ip             = "10.8.0.228"
    secondary_private_ip   = var.fw01_untrust_ha_ip
    assign_public_ip       = false
    skip_source_dest_check = true
  },
  {
    # port4: dedicated heartbeat
    name                   = "FW01-HEARTBEAT"
    hostname_label         = "fw01-heartbeat"
    subnet_id              = oci_core_subnet.heartbeat.id
    private_ip             = "10.8.0.244"
    secondary_private_ip   = null
    assign_public_ip       = false
    skip_source_dest_check = true
  }
]

  depends_on = [oci_core_app_catalog_subscription.sub]
}

module "fw_vm_02" {
  source = "./modules/fortigate_vm"

  name                = "FW02-VM"
  compartment_id      = var.compartment_ocid
  availability_domain = local.ad_name
  image_id            = local.image_id
  ssh_public_key      = local.ssh_public_key

  shape                   = var.shape
  ocpus                   = var.ocpus
  memory_in_gbs           = var.memory_in_gbs
  boot_volume_size_gb     = var.boot_volume_size_gb
  boot_volume_vpus_per_gb = var.boot_volume_vpus_per_gb

  # VNICs: [0] MGMT  [1] Indoor  [2] Untrust  [3] Heartbeat
  
vnics = [
  {
    # port1: dedicated standby management IP
    name                   = "FW02-MGMT"
    hostname_label         = "fw02-mgmt"
    subnet_id              = oci_core_subnet.mgmt.id
    private_ip             = "10.8.0.130"
    secondary_private_ip   = null
    assign_public_ip       = true
    skip_source_dest_check = false
  },
  {
    # port2: indoor/trust
    name                   = "FW02-INDOOR"
    hostname_label         = "fw02-indoor"
    subnet_id              = oci_core_subnet.indoor.id
    private_ip             = "10.8.0.194"
    secondary_private_ip   = null
    assign_public_ip       = false
    skip_source_dest_check = true
  },
  {
    # port3: untrust
    name                   = "FW02-UNTRUST"
    hostname_label         = "fw02-untrust"
    subnet_id              = oci_core_subnet.untrust.id
    private_ip             = "10.8.0.226"
    secondary_private_ip   = null
    assign_public_ip       = false
    skip_source_dest_check = true
  },
  {
    # port4: dedicated heartbeat
    name                   = "FW02-HEARTBEAT"
    hostname_label         = "fw02-heartbeat"
    subnet_id              = oci_core_subnet.heartbeat.id
    private_ip             = "10.8.0.242"
    secondary_private_ip   = null
    assign_public_ip       = false
    skip_source_dest_check = true
  }
]


  depends_on = [oci_core_app_catalog_subscription.sub]
}


resource "oci_core_public_ip" "shared_traffic" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "FGT-HA-SHARED-TRAFFIC-PIP"

  # FW01 port3's secondary private IP is the initial association.
  private_ip_id = module.fw_vm_01.secondary_private_ip_ids["2"]

  # FortiGate's OCI Fabric connector moves this association during HA.
  lifecycle {
    ignore_changes = [private_ip_id]
  }
}


# ---------------- Outputs ----------------
output "vm_public_ips" {
  value = {
    (module.fw_vm_01.name) = module.fw_vm_01.public_ip
    (module.fw_vm_02.name) = module.fw_vm_02.public_ip
  }
}
output "vm_private_ips" {
  value = {
    (module.fw_vm_01.name) = module.fw_vm_01.private_ip
    (module.fw_vm_02.name) = module.fw_vm_02.private_ip
  }
}
output "vm_login" {
  value = {
    (module.fw_vm_01.name) = "https://${module.fw_vm_01.public_ip} (user: admin, password: ${module.fw_vm_01.id})"
    (module.fw_vm_02.name) = "https://${module.fw_vm_02.public_ip} (user: admin, password: ${module.fw_vm_02.id})"
  }
}
output "marketplace_available_versions" {
  value = local.use_mp ? [for p in data.oci_marketplace_listing_packages.all[0].listing_packages : p.package_version] : []
}
output "selected_image_id" {
  value = local.image_id
}


output "fw01_management_public_ip" {
  value = module.fw_vm_01.public_ip
}

output "fw02_management_public_ip" {
  value = module.fw_vm_02.public_ip
}

output "shared_traffic_public_ip" {
  value = oci_core_public_ip.shared_traffic.ip_address
}

output "fw01_indoor_ha_ip" {
  value = module.fw_vm_01.secondary_private_ip_addresses["1"]
}

output "fw01_untrust_ha_ip" {
  value = module.fw_vm_01.secondary_private_ip_addresses["2"]
}
