# OpenStack image
image_name = "Ubuntu 26.04 (Switch Cloud)"

# login node
login_node_flavor_name      = "c002r004"
login_node_boot_volume_size = 50

# slurm master
slurm_master_flavor_name      = "c002r004"
slurm_master_boot_volume_size = 20

# slurm workers. 0: the compute nodes are elastic, slurmctld creates and
# deletes them (slurm_install_cloud_* in ansible/inventory/group_vars/all).
# Set a count here to also have permanent workers.
slurm_worker_count            = 0
slurm_worker_flavor_name      = "c002r004"
slurm_worker_boot_volume_size = 20

# nfs server
nfs_server_flavor_name      = "c002r004"
nfs_server_boot_volume_size = 20
nfs_server_data_volume_size = 20
