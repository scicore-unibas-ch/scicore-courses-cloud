# OpenStack image
image_name = "Ubuntu 26.04 (Switch Cloud)"

# login node
login_node_flavor_name      = "c032r064"
login_node_boot_volume_size = 100

# slurm master
slurm_master_flavor_name      = "c008r008"
slurm_master_boot_volume_size = 100

# slurm workers
slurm_worker_count            = 4
slurm_worker_flavor_name      = "c032r064"
slurm_worker_boot_volume_size = 100

# nfs server
nfs_server_flavor_name      = "c016r032"
nfs_server_boot_volume_size = 100
nfs_server_data_volume_size = 500
