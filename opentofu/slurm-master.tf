module "slurm_master" {
  source = "./modules/compute_node"

  name             = var.slurm_master_vm_name
  flavor_name      = var.slurm_master_flavor_name
  boot_volume_size = var.slurm_master_boot_volume_size
  image_id         = data.openstack_images_image_v2.image.id
  network_name     = data.openstack_networking_network_v2.private_net.name
  key_pair         = openstack_compute_keypair_v2.tofu_bootstrap_key.name

  # these tags define the groups this machine belongs to in the ansible inventory
  tags = [
    "slurm_master",
    "slurm",
    "course",
  ]

  security_group_names = [
    openstack_networking_secgroup_v2.opentofu_default.name,
  ]
}

# Application credential used by the slurm master to create/delete the
# dynamic compute nodes (Slurm ResumeProgram/SuspendProgram). Ansible deploys
# it to the slurm master from the file written below.
#
# Creating an application credential needs tofu to authenticate with a user
# password/token or with an *unrestricted* application credential: Keystone
# refuses the request from a restricted one. The credential created here is
# restricted, so a leaked copy cannot mint further credentials.
#
# Query its details from the state with:
# $> tofu state pull | jq '.resources[] | select(.type == "openstack_identity_application_credential_v3") .instances[0].attributes'
resource "random_password" "slurm_master_app_cred_secret" {
  length  = 64
  special = false
}

resource "openstack_identity_application_credential_v3" "app_cred_slurm_master" {
  name         = "slurm_master_course"
  description  = "app credential used by the slurm master to boot and delete compute nodes"
  secret       = random_password.slurm_master_app_cred_secret.result
  roles        = ["member", "reader"]
  unrestricted = false
}

# gitignored (see .gitignore)
resource "local_sensitive_file" "slurm_master_app_cred" {
  filename        = "${path.module}/../ansible/inventory/group_vars/slurm_master/openstack_app_credential.yml"
  file_permission = "0600"
  content = yamlencode({
    slurm_master_openstack_app_cred_id     = openstack_identity_application_credential_v3.app_cred_slurm_master.id
    slurm_master_openstack_app_cred_secret = openstack_identity_application_credential_v3.app_cred_slurm_master.secret
  })
}
