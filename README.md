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

## Two kinds of cluster

The same code deploys the cluster in either shape, and **both run Slurm in
[configless mode](https://slurm.schedmd.com/configless_slurm.html)**: only
the slurm master holds `slurm.conf`, the login node (`sackd`) and the compute
nodes (`slurmd --conf-server`) fetch it from slurmctld.

| | permanent machines | compute nodes | pick it when |
|---|---|---|---|
| **dynamic** (default) | login node, NFS server, slurm master | created by slurmctld when jobs need them, deleted after 15 idle minutes | a course with bursts of work; nothing is paid for while idle |
| **static** | the three above plus the workers | always running | short courses, or when jobs must start without waiting ~2 min for a VM |

What selects the shape:

| | `slurm_worker_count` (tfvars) | `slurm_install_cloud_scheduling` (group_vars/all/slurm.yml) |
|---|---|---|
| dynamic | `0` | `true` |
| static | the number of workers | `false` |

Both can be on at once: permanent workers **and** cloud nodes for bursts.

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

With `slurm_worker_count = 0` (the default) this boots the three permanent
machines. Set it to the number of workers you want for a static cluster.

`slurm_worker_flavor_name` and `slurm_worker_boot_volume_size` also describe
the *elastic* compute nodes: `tofu apply` writes them to
`ansible/inventory/group_vars/all/compute_node.yml` (gitignored), the way it
writes the slurm master's application credential, so the cluster Ansible
configures matches the environment that was deployed. What a node of
that flavor really has - CPUs, memory, topology - is measured by
`playbooks/probe-compute-node.yml`, not written by hand.

## Configuring the machines (ansible)

```bash
$> cd ansible/
$> ansible-galaxy install -r requirements.yml
$> ansible course -m shell -a 'uname -r'      # check every machine answers
```

### A dynamic cluster (the default)

One command configures the machines and builds the image the compute nodes
boot from:

```bash
$> ansible-playbook playbooks/deploy.yml
```

The image is built only when it is missing, so running this again is cheap.
See [Compute nodes (elastic)](#compute-nodes-elastic) below for what the
build does and how to rebuild it.

### A static cluster

Set `slurm_worker_count` in the tfvars file and turn the cloud nodes off in
`ansible/inventory/group_vars/all/slurm.yml`:

```yaml
slurm_install_cloud_scheduling: false
```

Then no image is needed, and `site.yml` is the whole job:

```bash
$> ansible-playbook playbooks/site.yml
```

`deploy.yml` also works here: with cloud scheduling off it just runs
`site.yml` and builds nothing.

## Compute nodes (elastic)

The cluster keeps only three machines running: the login node, the NFS server
and the slurm master. Compute nodes are created by slurmctld when jobs need
them and deleted after 15 idle minutes (`slurm_install_cloud_*` in
`ansible/inventory/group_vars/all/slurm.yml`), so `slurm_worker_count` is 0.

They boot from an image built once per deployment, after the cluster is up
(the build reads the munge key from the slurm master and mounts the NFS
share). `deploy.yml` does the whole thing in one command - configure the
three machines, then build the image if it is missing:

```bash
$> cd ansible/
$> ansible-playbook playbooks/deploy.yml
```

Running it again is cheap: an image that already exists is left alone. To
rebuild it after changing what a compute node contains:

```bash
$> ansible-playbook playbooks/build-compute-image.yml -e compute_image_when_exists=replace
```

The build boots a builder VM, applies the Slurm compute-node role and the
`course_compute_node` role (the same users, NFS mount and cvmfs client the
permanent hosts get), cleans it, uploads it as a **private** image and
deletes the builder.

`sinfo` shows the nodes as `idle~` while they do not exist. Submitting a job
creates one, which takes about two minutes (the VM boots, then slurmd
registers with the slurm master); `/var/log/slurm/dynamic_nodes.log` on the
slurm master records every create and delete (warnings and errors also go to
syslog).

Two consequences of nodes coming and going:

- **Compute nodes change their SSH host key** every time they are re-created,
  so `known_hosts` warns. The course users already get
  `StrictHostKeyChecking no`.
- **DNS caching is off** on the three permanent machines: a re-created node
  keeps its name but gets a new IP.

## Stop and destroy all the machines

`tofu destroy` removes the three permanent machines, but **not** the compute
nodes: slurmctld created them, so they are not in the OpenTofu state and a
destroy leaves them running. Clean them up first (or afterwards):

```bash
$> cd ansible/
$> ansible-playbook playbooks/cleanup.yml --check   # preview
$> ansible-playbook playbooks/cleanup.yml
```

At the end of a course, to delete the compute-node image too:

```bash
$> ansible-playbook playbooks/cleanup.yml \
     -e '{"slurm_cleanup_images": ["course-compute-node"]}'
```


```bash
$> cd opentofu/
$> tofu destroy -var-file=environments/dev.tfvars   # or prod.tfvars
```
