# The elastic compute nodes are created by slurmctld, not by OpenTofu, so
# their flavor lives in Ansible - but which flavor a deployment wants is an
# environment decision, and that is what the tfvars files are. Write it into
# the inventory, the same way slurm-master.tf writes the application
# credential (both files are gitignored: they describe the deployment that
# exists, not the repository).
#
# slurm_worker_flavor_name is the same answer for a static worker and for an
# elastic one: what a compute node of this cluster is.
resource "local_file" "ansible_compute_node_flavor" {
  filename        = "${path.module}/../ansible/inventory/group_vars/all/compute_node_flavor.yml"
  file_permission = "0644"
  content = yamlencode({
    local_compute_node_flavor = var.slurm_worker_flavor_name
  })
}
