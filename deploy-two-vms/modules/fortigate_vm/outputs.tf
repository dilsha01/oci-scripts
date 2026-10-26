output "id" {
  description = "Instance OCID"
  value       = oci_core_instance.vm.id
}

output "name" {
  description = "Instance display name"
  value       = oci_core_instance.vm.display_name
}

output "private_ip" {
  description = "Primary (MGMT) private IP"
  value       = oci_core_instance.vm.private_ip
}

output "public_ip" {
  description = "Primary (MGMT) public IP address (if reserved public IP was created)"
  value       = try(oci_core_public_ip.reserved["0"].ip_address, null)
}

output "reserved_public_ips" {
  description = "Map of VNIC index => reserved public IP address for all VNICs that have assign_public_ip = true"
  value       = { for k, pip in oci_core_public_ip.reserved : k => pip.ip_address }
}

output "secondary_vnic_ids" {
  description = "Map of VNIC index => VNIC attachment OCID for secondary VNICs"
  value       = { for k, att in oci_core_vnic_attachment.secondary : k => att.id }
}


output "secondary_private_ip_ids" {
  description = "Secondary private IP OCIDs keyed by VNIC index"
  value = {
    for k, ip in oci_core_private_ip.secondary :
    k => ip.id
  }
}

output "secondary_private_ip_addresses" {
  description = "Secondary private IP addresses keyed by VNIC index"
  value = {
    for k, ip in oci_core_private_ip.secondary :
    k => ip.ip_address
  }
}
