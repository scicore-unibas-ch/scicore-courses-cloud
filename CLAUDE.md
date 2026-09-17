# scicore-courses-cloud — Project Context

OpenTofu + Ansible for the sciCORE course clusters on the SWITCH OpenStack
cloud (region `zhw`). `opentofu/` boots the VMs, `ansible/` configures them;
hosts land in inventory groups from the VM tags (`inventory/openstack.yml`).

## Status (2026-09-17)

**Slurm now comes from the `pescobar.slurm` collection** (role
`slurm_install`, github.com/pescobar/ansible-collection-slurm, cloned at
`../ansible-collection-slurm`), replacing the old `scicore.slurm` role
(`../ansible-role-slurm`, reference only — do not modify it). PRs #29 and #30
are merged.

- **Ubuntu 26.04** everywhere (`dev.tfvars`/`prod.tfvars`): its archive Slurm
  is 25.11, the floor for the collection's accounting module. 24.04 ships
  23.11.
- **Static Slurm config** — no configless, no cloud/elastic scheduling. The
  old `slurm.conf.course.j2` was deleted (it was a half-migrated cloud config:
  `SuspendTime` with no suspend script deployed, node lines taking
  `CoresPerSocket` from the threads-per-core fact). Recover it from git
  history when the cloud-scheduling work starts.
- Slurm runs in **its own play** in `configure.yml` (`hosts: slurm`), not
  `import_role` + `when`: the role's `run_once` munge-key read must not depend
  on which host is first in the play.
- Course users are added to accounting by the role's **lua auto-add plugin**
  (`slurm_install_job_submit_lua_template`). Do not combine it with
  `slurm_acct_purge`, which would delete those users again.

**Verified on a dev deployment (5 VMs, then destroyed):** `configure.yml`
clean on all hosts; `sinfo` shows partition `compute` with both workers idle;
`user01` submits from the login node, the job runs on a worker and the user is
auto-added to accounting; a job over its `--mem` ends `OUT_OF_MEMORY`.

**Not yet run on 26.04:** `cvmfs-presync.yml`, `rstudio.yml`, `ondemand.yml`
(the rest of `site.yml`). Open OnDemand and the CVMFS packages are the likely
breakages.

## Next steps

1. Run the rest of `site.yml` on a dev deployment (Open OnDemand, RStudio,
   CVMFS) and fix what 26.04 breaks.
2. Move `slurm_install_dbd_storage_password` (still plaintext in
   `group_vars/all/slurm.yml`) to ansible-vault.
3. Later, in the collection first: configless mode (`sackd` on the login
   node), then OpenStack elastic scheduling (resume/suspend programs,
   `clouds.yaml` on the controller, the commented-out app-credential
   resources in `opentofu/slurm-master.tf`), then an aux script to build
   compute-node images.
4. Consider declaring the course accounts/users with the collection's
   `slurm_acct` role instead of the lua auto-add plugin.

## Gotchas found the hard way

- **Deploying needs python ≥ 3.12** (ansible 14). Set up with `uv` as the
  README says; `python3 -m venv` may lack `ensurepip` on some machines.
- **`ansible` 10.7 breaks the openstack inventory** (bundled
  `openstack.cloud` 2.3.0 calls `openstack.version.__version__`, gone in
  openstacksdk 4) — hence the ansible 14.4.0 pin.
- **Third-party roles gate on the OS version**: `willshersystems.sshd`
  v0.27.1 ends the play with `meta: end_host` on an unknown OS, which
  silently skipped the rest of `configure.yml` (no course users were
  created). Pinned v0.34.0. Check the same pattern when a role misbehaves.
- **`/tmp` is per-node**; job output must go to `/shared/home/...` (NFS).
- **Application credentials are bound to one project**: adding `project_id`
  to `clouds.yaml` does not rescope them. The credential for this work is
  scoped to `SIB-Training #woVM`.
- **A failed apply can orphan a security group** (Neutron 500 while deleting
  its default rules): the group exists in the cloud but not in the state, and
  the next apply fails with "Multiple security_group matches found". Delete
  the orphan (the one with no ports attached), then re-apply.
- **One state, no workspaces**: `dev.tfvars` and `prod.tfvars` produce the
  same VM names, so only one environment can exist at a time. Pass
  `-var ssh_key_name=<name>` when a keypair of the default name already
  exists in the project.

## Conventions

- Work on a branch, open a PR, let CI (`Lint`: tofu fmt/validate +
  ansible-lint) pass; PRs are merged by the user, then the branch is deleted.
- Never run `tofu apply`/`destroy` without asking first — it creates billable
  cloud resources.
