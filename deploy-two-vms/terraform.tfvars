region           = "ap-hyderabad-1"
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaavnwzahmwtpputxfnfrds57n7doyqig4532egavitx64o5kpbpbva"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaapn6w4llsutvzm42o527nap5dghqnbnoikwxgzwosslmvr5fvp7ha"

vcn_ocid    = "ocid1.vcn.oc1.ap-hyderabad-1.amaaaaaazv23a4aaxicwhtrk5ymgr7grbtni7jh5jjhk3bjelebl3u6r7nqa"

ad_index = 0

shape         = "VM.Standard.E4.Flex"
ocpus         = 4
memory_in_gbs = 16

image_source                = "marketplace"
marketplace_listing_name    = "FortiGate Next-Gen Firewall (BYOL)"
marketplace_package_version = "8.0.1_(_X64_)"
accept_marketplace_terms    = true

vcn_name    = "MY-TEST-VCN"
subnet_name = "MY-TEST-SUBNET-01"

boot_volume_size_gb     = 50
boot_volume_vpus_per_gb = 10


# Movable secondary private IPs, initially attached to FW01
fw01_indoor_ha_ip  = "10.8.0.197"
fw01_untrust_ha_ip = "10.8.0.229"

# Protected workload subnet CIDR, only if creating a new subnet
#webapp_subnet_cidr = "REPLACE_WITH_APPROVED_WEBAPP_CIDR"
