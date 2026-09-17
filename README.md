# sciCORE courses

[![Lint](https://github.com/scicore-unibas-ch/scicore-courses-cloud/actions/workflows/lint.yml/badge.svg)](https://github.com/scicore-unibas-ch/scicore-courses-cloud/actions/workflows/lint.yml)

OpenTofu and ansible code used to boot and configure the infrastructure for the sciCORE courses

## Setting up the control host

### Install OpenTofu

Install OpenTofu using your preferred method (tested with version 1.9.1)

### Install Ansible and Openstack client inside a python virtualenv

```bash
$> git clone https://github.com/scicore-unibas-ch/scicore-courses-cloud.git
$> cd scicore-courses-cloud
$> python3 -m venv .venv
$> source .venv/bin/activate
$> pip install -U pip
$> pip install -r ansible/requirements.txt
$> source ~/your/openstack-openrc.sh
$> openstack server list
```

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

## Stop and destroy all the machines

```bash
$> cd opentofu/
$> tofu destroy -var-file=environments/dev.tfvars   # or prod.tfvars
```
