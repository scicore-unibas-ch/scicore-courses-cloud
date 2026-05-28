resource "openstack_networking_secgroup_v2" "opentofu_default" {
  name                 = "opentofu_default"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "allow_any_outgoing_traffic_ipv4" {
  security_group_id = openstack_networking_secgroup_v2.opentofu_default.id
  description       = "allow any outgoing traffic"
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "allow_any_from_lan" {
  security_group_id = openstack_networking_secgroup_v2.opentofu_default.id
  description       = "allow any from LAN"
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.opentofu_default.id
}

resource "openstack_networking_secgroup_v2" "opentofu_login_node" {
  name                 = "opentofu_login_node"
  delete_default_rules = true
}

locals {
  login_node_ingress_rules = {
    ssh     = { port = 22, description = "allow ssh from internet" }
    rstudio = { port = 8787, description = "allow rstudio from internet" }
    http    = { port = 80, description = "allow http for lets encrypt acme + redirect to https" }
    https   = { port = 443, description = "allow https for open ondemand" }
  }
}

resource "openstack_networking_secgroup_rule_v2" "login_node_ingress" {
  for_each = local.login_node_ingress_rules

  security_group_id = openstack_networking_secgroup_v2.opentofu_login_node.id
  description       = each.value.description
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = "0.0.0.0/0"
}
