output "id" {
  value = oci_core_instance.vm.id
}
output "name" {
  value = oci_core_instance.vm.display_name
}
output "public_ip" {
  value = oci_core_instance.vm.public_ip
}
output "private_ip" {
  value = oci_core_instance.vm.private_ip
}