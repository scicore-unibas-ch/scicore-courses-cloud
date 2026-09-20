# sciCORE courses

[![Lint](https://github.com/scicore-unibas-ch/scicore-courses-cloud/actions/workflows/lint.yml/badge.svg)](https://github.com/scicore-unibas-ch/scicore-courses-cloud/actions/workflows/lint.yml)

OpenTofu and ansible code used to boot and configure the infrastructure for the sciCORE courses

## Setting up the control host

### Install OpenTofu

Install OpenTofu using your preferred method (tested with version 1.9.1)

### Install Ansible and Openstack client with uv

We use [uv](https://docs.astral.sh/uv/) to install the python version and the
python dependencies. Install uv if you don't have it yet:

```bash
$> curl -LsSf https://astral.sh/uv/install.sh | sh
```

`ansible` requires python 3.12 or newer. uv downloads it if it's missing, so
you don't need a system python of that version:

```bash
$> git clone https://github.com/scicore-unibas-ch/scicore-courses-cloud.git
$> cd scicore-courses-cloud
$> uv venv --python 3.12 .venv
$> source .venv/bin/activate
$> uv pip install -r ansible/requirements.txt
$> source ~/your/openstack-openrc.sh
$> openstack server list
```

The openstack client also reads `~/.config/openstack/clouds.yaml` instead of
an openrc file; select an entry from it with `export OS_CLOUD=<cloud-name>`.

## Booting the machines (OpenTofu)

Environment-specific values (flavors, volume sizes, image names, network names) are defined
in `opentofu/environments/dev.tfvars` and `opentofu/environments/prod.tfvars`.
Variable definitions and descriptions live in `opentofu/variables.tf`.

```bash
$> cd opentofu/
$> tofu init

# deploy dev environment
$> tofu plan -var-file=environments/dev.tfvars
$> tofu apply -var-file=environments/dev.tfvars

# deploy prod environment
$> tofu plan -var-file=environments/prod.tfvars
$> tofu apply -var-file=environments/prod.tfvars

$> openstack server list
```

## Configuring the machines (ansible)

```bash
$> cd ansible/
$> ansible-galaxy install -r requirements.yml
$> ansible course -m shell -a 'uname -r'
$> ansible-playbook playbooks/site.yml
```

## Compute nodes (elastic)

The cluster keeps only three machines running: the login node, the NFS server
and the slurm master. Compute nodes are created by slurmctld when jobs need
them and deleted after 15 idle minutes (`slurm_install_cloud_*` in
`ansible/inventory/group_vars/all/slurm.yml`), so `slurm_worker_count` is 0.

They boot from an image that must be built once per deployment, after the
cluster is up (the build reads the munge key from the slurm master and mounts
the NFS share):

```bash
$> cd ansible/
$> ansible-playbook playbooks/build-compute-image.yml      -e compute_image_name=course-compute-node-2026-09-20
```

The playbook boots a builder VM, applies the Slurm compute-node role and the
`course_compute_node` role (the same users, NFS mount and cvmfs client the
permanent hosts get), cleans it, snapshots it to a **private** image and
deletes the builder. Then point `slurm_install_cloud_image` at the new name
and re-run `ansible-playbook playbooks/site.yml`.

`sinfo` shows the nodes as `idle~` while they do not exist. Submitting a job
creates one; `/var/log/slurm/dynamic_nodes.log` on the slurm master records
every create and delete (warnings and errors also go to syslog).

Two consequences of nodes coming and going:

- **Compute nodes change their SSH host key** every time they are re-created,
  so `known_hosts` warns. The course users already get
  `StrictHostKeyChecking no`.
- **DNS caching is off** on the three permanent machines: a re-created node
  keeps its name but gets a new IP.

## Stop and destroy all the machines

```bash
$> cd opentofu/
$> tofu destroy -var-file=environments/dev.tfvars   # or prod.tfvars
```
