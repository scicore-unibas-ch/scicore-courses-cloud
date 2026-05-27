resource "openstack_blockstorage_volume_v3" "boot" {
  name     = "${var.name}-boot"
  size     = var.boot_volume_size
  image_id = var.image_id
}

# Created only for nodes with a floating IP so that security groups can be
# attached at the port level. This avoids a known OpenStack bug where SGs
# placed on the instance are not applied until after the first refresh.
resource "openstack_networking_port_v2" "port" {
  count              = var.attach_floating_ip ? 1 : 0
  name               = "${var.name}-port"
  network_id         = var.network_id
  admin_state_up     = true
  security_group_ids = var.security_group_ids
}

resource "openstack_compute_instance_v2" "instance" {
  name        = var.name
  flavor_name = var.flavor_name
  key_pair    = var.key_pair
  tags        = var.tags

  # Security groups are attached at the port level for floating-IP nodes (see
  # openstack_networking_port_v2 above). For internal nodes they go here.
  security_groups = var.attach_floating_ip ? null : var.security_group_names

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.boot.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  dynamic "network" {
    for_each = var.attach_floating_ip ? [] : [1]
    content {
      name = var.network_name
    }
  }

  dynamic "network" {
    for_each = var.attach_floating_ip ? [1] : []
    content {
      port = openstack_networking_port_v2.port[0].id
    }
  }
}

resource "openstack_networking_floatingip_v2" "fip" {
  count = var.attach_floating_ip ? 1 : 0
  pool  = var.public_network_name
}

resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  count       = var.attach_floating_ip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.fip[0].address
  port_id     = openstack_networking_port_v2.port[0].id
}

# Optional extra data volume (e.g. NFS shared storage)
resource "openstack_blockstorage_volume_v3" "data" {
  count = var.extra_data_volume_size > 0 ? 1 : 0
  name  = "${var.name}-data-volume"
  size  = var.extra_data_volume_size
}

resource "openstack_compute_volume_attach_v2" "data_attach" {
  count       = var.extra_data_volume_size > 0 ? 1 : 0
  instance_id = openstack_compute_instance_v2.instance.id
  volume_id   = openstack_blockstorage_volume_v3.data[0].id
}
