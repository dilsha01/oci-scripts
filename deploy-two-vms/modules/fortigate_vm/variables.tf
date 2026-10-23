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
variable "subnet_id" { type = string }
variable "private_ip" { type = string }
variable "vnic_name" {
  type    = string
  default = "vnic01"
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