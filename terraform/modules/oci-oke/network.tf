resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.name_prefix}-vcn"
  dns_label      = "solana"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
}

# NO SERVICE GATEWAY, deliberately.
#
# A service gateway lets a PRIVATE subnet reach OCI services (Object Storage, the OKE control
# plane) without traversing the internet. These workers sit in a PUBLIC subnet with public IPs
# and an internet gateway (ADR 0009), so they already reach everything, and the gateway would be
# redundant.
#
# It is also not merely redundant, it is rejected. Adding an "All Services" service-gateway route
# alongside an internet-gateway default route in the same table fails at apply time with:
#
#   400-InvalidParameter, Internet Gateway target cannot be used together with Service Gateway
#   target for All Services in the same routing table
#
# If these workers were ever moved to a private subnet, the gateway becomes REQUIRED - without it
# nodes come up NotReady with a generic image-pull timeout that names nothing useful.

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-rt-public"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

# Workers are PUBLIC. A gossip participant must be reachable on UDP from arbitrary peers.
# This contradicts the usual "prefer private subnets" guidance, which is why it is ADR 0009 and
# not a silent setting.
resource "oci_core_subnet" "workers" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = cidrsubnet(var.vcn_cidr, 8, 1)
  display_name               = "${var.name_prefix}-workers"
  dns_label                  = "workers"
  route_table_id             = oci_core_route_table.public.id
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "api" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = cidrsubnet(var.vcn_cidr, 12, 0)
  display_name               = "${var.name_prefix}-api"
  dns_label                  = "api"
  route_table_id             = oci_core_route_table.public.id
  prohibit_public_ip_on_vnic = false
}
