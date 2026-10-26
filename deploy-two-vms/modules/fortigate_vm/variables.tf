variable "name" {
  description = "Instance display name"
  type        = string
}
variable "compartment_id" { type = string }
variable "availability_domain" { type = string }
variable "fault_domain" {
  type    = string
  default = null
}

variable "vnics" {
  description = <<-EOT
    Four VNIC configurations for the FortiGate VM (index 0 = primary/MGMT).
    Fields:
      name                   – display name
      hostname_label         – DNS hostname label
      subnet_id              – subnet OCID
      private_ip             – primary private IP address
      secondary_private_ip   – (optional) additional private IP on this VNIC
      assign_public_ip       – (optional, default false) create & attach a RESERVED public IP
      skip_source_dest_check – (optional, default true)
  EOT

  type = list(object({
    name                   = string
    hostname_label         = string
    subnet_id              = string
    private_ip             = string
    secondary_private_ip   = optional(string)
    assign_public_ip       = optional(bool, false)
    skip_source_dest_check = optional(bool, true)
  }))

  validation {
    condition     = length(var.vnics) == 4
    error_message = "Exactly four VNIC configurations are required."
  }
}

variable "image_id" { type = string }
variable "ssh_public_key" { type = string }

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