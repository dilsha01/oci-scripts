region           = "ap-hyderabad-1"
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaavnwzahmwtpputxfnfrds57n7doyqig4532egavitx64o5kpbpbva"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaapn6w4llsutvzm42o527nap5dghqnbnoikwxgzwosslmvr5fvp7ha"

ad_index = 0

shape         = "VM.Standard.E4.Flex"
ocpus         = 4
memory_in_gbs = 16

image_source                = "marketplace"
marketplace_listing_name    = "FortiGate Next-Gen Firewall (BYOL)"
marketplace_package_version = "8.0.1_(_X64_)"
accept_marketplace_terms    = true

vcn_name    = "Test-VCN"
subnet_name = "public subnet-Test-VCN"

boot_volume_size_gb     = 50
boot_volume_vpus_per_gb = 10