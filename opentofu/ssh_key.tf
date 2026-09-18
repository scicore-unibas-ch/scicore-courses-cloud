locals {
  ssh_key_file = pathexpand("~/.ssh/id_ed25519_tofu")
}

resource "null_resource" "ssh_keygen" {
  # re-run when the key path changes (e.g. an existing state from the old RSA key)
  triggers = {
    ssh_key_file = local.ssh_key_file
  }

  provisioner "local-exec" {
    command = <<EOT
if [ ! -f "${local.ssh_key_file}" ]; then
  ssh-keygen -t ed25519 \
    -f "${local.ssh_key_file}" \
    -C "opentofu-bootstrap" \
    -N ""
fi
EOT
  }
}

data "local_file" "ssh_public_key" {
  filename = "${local.ssh_key_file}.pub"

  depends_on = [
    null_resource.ssh_keygen
  ]
}

resource "openstack_compute_keypair_v2" "tofu_bootstrap_key" {
  name       = var.ssh_key_name
  public_key = trimspace(data.local_file.ssh_public_key.content)
}
