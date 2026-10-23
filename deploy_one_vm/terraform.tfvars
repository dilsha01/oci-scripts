region           = "ap-hyderabad-1"            # e.g. ap-singapore-1
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaavnwzahmwtpputxfnfrds57n7doyqig4532egavitx64o5kpbpbva"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaapn6w4llsutvzm42o527nap5dghqnbnoikwxgzwosslmvr5fvp7ha"   # bwg-ebs-network

instance_name = "TestFW-VM01"
ad_index      = 0                                # AD-1

shape         = "VM.Standard.E4.Flex"
ocpus         = 4
memory_in_gbs = 16

image_source                = "marketplace"
marketplace_listing_name    = "FortiGate Next-Gen Firewall (BYOL)"
# marketplace_listing_id    = "ocid1.marketplacelisting..."   # use if the name lookup fails
marketplace_package_version = "8.0.1_(_X64_)"
accept_marketplace_terms    = true   # false if already accepted manually

vcn_name       = "MY-TEST-VCN"
subnet_name    = "MY-TEST-SUBNET-01"
vnic_name      = "vnic01"
private_ip     = "10.8.0.4"
# hostname_label = "fgt01"

boot_volume_size_gb     = 50
boot_volume_vpus_per_gb = 10

# ssh_public_key = ""   # empty = generate a key pair and save <instance_name>.key / .key.pub next to main.tf