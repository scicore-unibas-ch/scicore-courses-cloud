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

# the resource below can be used in case we configure slurm in dynamic mode
# by now this is here just as reference
# # this is the ramdom password used by the application credential below
# resource "random_password" "slurm_master_app_cred_password" {
#   length           = 64
#   special          = false
#   #override_special = "_%@"
# }

# # This application credential is used by the slurm master to start/stop dynamic compute nodes
# # This app cred is deployed to /etc/openstack/clouds.yaml in the slurm master host
# # You can query details from terraform state using this command:
# # $> tofu state pull | jq '.resources[] | select(.type == "openstack_identity_application_credential_v3") .instances[0].attributes'
# resource "openstack_identity_application_credential_v3" "app_cred_slurm_master" {
#   name        = "slurm_master_course"
#   description = "app credential used by slurm master to boot compute nodes"
#   secret      = random_password.slurm_master_app_cred_password.result
#   roles       = ["member","reader"]
#   unrestricted = "false"
#   #expires_at  = "2019-02-13T12:12:12Z"
# }

# resource "local_file" "slurm_master_app_cred" {
#   filename        = "${path.module}/../ansible/inventory/group_vars/slurm_master/openstack_app_credential.yml"
#   file_permission = "0600"
#   content         = yamlencode({
#     slurm_master_openstack_app_cred_id     = openstack_identity_application_credential_v3.app_cred_slurm_master.id
#     slurm_master_openstack_app_cred_secret = openstack_identity_application_credential_v3.app_cred_slurm_master.secret
#   })
# }
