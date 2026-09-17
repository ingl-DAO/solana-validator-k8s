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

# Without a service gateway the nodes sit NotReady with a generic image-pull timeout and nothing
# names the cause. Budget an hour for this the first time you hit it.
data "oci_core_services" "all_oci" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-sgw"
  services {
    service_id = data.oci_core_services.all_oci.services[0].id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-rt-public"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
  route_rules {
    destination       = data.oci_core_services.all_oci.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
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
