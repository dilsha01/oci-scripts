region           = "ap-hyderabad-1"
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaavnwzahmwtpputxfnfrds57n7doyqig4532egavitx64o5kpbpbva"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaapn6w4llsutvzm42o527nap5dghqnbnoikwxgzwosslmvr5fvp7ha"

vcn_ocid = "ocid1.vcn.oc1.ap-hyderabad-1.amaaaaaazv23a4aaxicwhtrk5ymgr7grbtni7jh5jjhk3bjelebl3u6r7nqa"

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

# ---------------- Route Tables & Gateways ----------------
# Provide existing gateway OCIDs if available; if left empty (""), Terraform automatically creates them.
internet_gateway_ocid = "" # e.g. "ocid1.internetgateway.oc1..."
nat_gateway_ocid      = "" # e.g. "ocid1.natgateway.oc1..."
service_gateway_ocid  = "" # e.g. "ocid1.servicegateway.oc1..."
drg_ocid              = "" # e.g. "ocid1.drg.oc1..."

# Automatic gateway creation flags (default is true for all)
create_internet_gateway = true
create_nat_gateway      = true
create_service_gateway  = true
create_drg              = true

# Legacy list of spoke CIDRs routed via DRG and FortiGate. When using the
# spokes map below, Terraform derives these CIDRs automatically.
#spoke_cidrs = ["10.9.0.0/24", "10.10.0.0/24"]

# Managed spoke-side configuration. Uncomment and replace every placeholder to
# create each VCN attachment, assign RT-Spoke, and associate a new route table
# with each listed workload subnet. route_cidrs defaults to ["0.0.0.0/0"].
# The new route table replaces the subnet's current route-table association.
#
 spokes = {
   spoke_a = {
     compartment_id      = "ocid1.compartment.oc1..aaaaaaaapn6w4llsutvzm42o527nap5dghqnbnoikwxgzwosslmvr5fvp7ha"
     vcn_id              = "ocid1.vcn.oc1.ap-hyderabad-1.amaaaaaazv23a4aavlmi67o3tenuemrdbeb7mbtfqnlvj3rjsftujo2tobsa"
     cidrs               = ["10.9.0.0/24"]
     workload_subnet_ids = ["ocid1.subnet.oc1.ap-hyderabad-1.aaaaaaaaepznu7mj3vcqzbgwe6j2vkpakprncca5fqr7fa56in54oh7ynnia"]
     route_cidrs       = ["0.0.0.0/0"]
   }
   spoke_b = {
     compartment_id      = "ocid1.compartment.oc1..aaaaaaaapn6w4llsutvzm42o527nap5dghqnbnoikwxgzwosslmvr5fvp7ha"
     vcn_id              = "ocid1.vcn.oc1.ap-hyderabad-1.amaaaaaazv23a4aaf2exwtjgsi6n2ndlekqfgcdofxg7io2lk6fxuvtzvzla"
     cidrs               = ["10.10.0.0/24"]
     workload_subnet_ids = ["ocid1.subnet.oc1.ap-hyderabad-1.aaaaaaaakdxbr7p73xedwcfetc2a6hnkval2bpsbbqiqvplwudvuapaz2fma"]
     route_cidrs       = ["0.0.0.0/0"]
   }
 }

# On-Premises CIDRs routed through FortiGate (e.g. ["172.16.0.0/16"])
onprem_cidrs = []

# Manage full DRG Transit Routing (RT-Spoke, RT-Hub, RT-OnPrem, Import-Hub)
manage_drg_transit_routing = true

# ---------------- FortiGate HA IAM Roles & Policies ----------------
create_iam_resources    = true
dynamic_group_name      = "fgt-ha-dynamic-group"
policy_name             = "fgt-ha-policy"
use_granular_iam_policy = true # true = 7 minimum sufficient permissions, false = virtual-network-family

