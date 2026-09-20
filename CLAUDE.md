# scicore-courses-cloud — Project Context

OpenTofu + Ansible for the sciCORE course clusters on the SWITCH OpenStack
cloud (region `zhw`). `opentofu/` boots the VMs, `ansible/` configures them;
hosts land in inventory groups from the VM tags (`inventory/openstack.yml`).

## Status (2026-09-18)

**Slurm now comes from the `pescobar.slurm` collection** (role
`slurm_install`, github.com/pescobar/ansible-collection-slurm, cloned at
`../ansible-collection-slurm`), replacing the old `scicore.slurm` role
(`../ansible-role-slurm`, reference only — do not modify it). PRs #29–#44
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

**Verified on dev deployments (5 VMs, destroyed after each):**

- 2026-09-17: `configure.yml` clean on all hosts; `sinfo` shows partition
  `compute` with both workers idle; `user01` submits from the login node, the
  job runs on a worker and the user is auto-added to accounting; a job over
  its `--mem` ends `OUT_OF_MEMORY`.
- 2026-09-18: the **full `site.yml`** runs clean on a fresh deployment
  (first run ~14-16 min, re-run ~4 min): a worker job sees `/cvmfs`; R 4.6.1
  loads the r2u CRAN/Bioconductor packages and `rstudio-server` answers on
  :8787; Open OnDemand serves `https://<fip-dashed>.sslip.io` with a Let's
  Encrypt cert and `user01` logs into the dashboard (PAM basic auth, default
  course password is in `group_vars/all/local_users.yml`). Launching a
  `bc_desktop` session was not tested.
- 2026-09-18 (later): **idempotency verified** — a further `site.yml` run was
  `changed=0` on every host (#36, #37 confirmed on real VMs; the one-time
  `autoremove` on the second run is expected). **#43 verified**: on a fresh
  deploy all 5 hosts needed a reboot; the four others rebooted first, then the
  login node, no timeout; `user01` ran `srun -N2 hostname` on both workers.
  **#44** (slurm master app credential) applied and verified: the credential
  authenticates and lists the project's servers. The cluster was destroyed
  afterwards.

**Idempotency fixes (PRs #33, #34, #37):** `update_ood_portal` ran with
`changed_when: true` and restarted apache every run (now
`--detailed-exitcodes --force`); the cvmfs presync shell tasks (now
`changed_when: false`); `r-base` installed before the r2u repo + pin, so the
next dist-upgrade swapped 15 `r-cran-*` packages (now installed after the pin).

**Other changes 2026-09-18:** R packages install with one `apt` call per list
(#32); CI installs with `uv` + its cache instead of pip (lint job ~72 s →
~30 s), runs on `ubuntu-26.04`, `setup-opentofu@v2`, no ansible-lint warnings
(#35); the tofu bootstrap key is ed25519, `~/.ssh/id_ed25519_tofu` (#36);
`apt-dist-upgrade.yml` reboots the login node after the other hosts (#43);
`opentofu/slurm-master.tf` creates the slurm master's application credential
(#44).

## Current work: configless + elastic compute nodes

**Wired up 2026-09-20 (not yet deployed).** The collection side is merged
(pescobar/ansible-collection-slurm PRs #6 configless, #7 elastic nodes,
#8 compute-node image) and this repo now uses it:

- `group_vars/all/slurm.yml`: `slurm_install_configless: true`,
  `slurm_install_manage_etc_hosts: false`, `slurm_install_cloud_scheduling:
  true` with 4 `compute-[01-04]` nodes (c002r004, image
  `slurm_install_cloud_image`, network UNIBAS, keypair opentofu_key, secgroup
  opentofu_default) and the app credential from #44.
- `slurm_worker_count = 0` in both tfvars: no permanent workers.
- `configure.yml` turns the systemd-resolved cache off on the permanent hosts
  (a re-created node keeps its name and gets a new IP) and now includes
  `tasks/course_users.yml`, which the image build uses too so the accounts
  cannot drift. The NFS mount is by name (`nfs-server:/shared`), not by the
  server's IP: an image cannot carry an address.
- `custom_roles/course_compute_node` (new `roles_path` entry - `ansible/roles/`
  is the gitignored galaxy target) applies the course side to the image;
  `playbooks/build-compute-image.yml` imports the collection's build playbook,
  with the builder's settings in `group_vars/_compute_image_builder/`
  (it needs its own ssh/ProxyCommand and nfs vars: the host is added at run
  time and is in no other group).

**Tearing down:** `tofu destroy` does NOT delete the compute nodes (slurmctld
creates them, so they are not in the state - a leftover node survived the
2026-09-20 teardown). Run `playbooks/cleanup.yml` first (add
`-e '{"slurm_cleanup_images": ["course-compute-node"]}'` to drop the image at
the end of a course), then destroy, then re-run destroy to confirm 0
resources.

**Order of operations on a fresh deployment:** `tofu apply` ->
`playbooks/deploy.yml` (site.yml + the compute-node image, built only when
missing) -> submit a job and watch `/var/log/slurm/dynamic_nodes.log` on the
slurm master. The image name is stable, so nothing has to be edited between
steps; rebuild it with `-e compute_image_when_exists=replace`.

**Verified on the real cloud 2026-09-20** (dev deployment, 3 VMs + elastic
nodes): `site.yml` clean in 14 min; the image build produced a private image;
`sbatch` as user01 created compute-01 (~1m50s VM boot, then slurmd
registered over configless), the job ran and was recorded in accounting, with
`/shared` and `/cvmfs` both working on the created node; `scontrol update
state=POWER_DOWN_FORCE` deleted the VM by its recorded id and left no volume.

**What the first live run cost us** (all fixed, see this repo's PR #47 and the
collection's #9): SWITCH flavors have disk=0 so everything must boot from a
volume; play vars in the collection's build playbook overrode this repo's
inventory (`volume_size`, and `compute_image_extra_roles`, which would have
produced an image with no course configuration); the implicit localhost
inherits no group_vars (hence `inventory/localhost.yml`); the login node
dropped the ansible tunnel during long tasks ("Timeout, client not
responding") until ssh keepalives and ClientAliveCountMax 20 were in place;
and handlers never flushed before the image was snapshotted, so the first
image had no /cvmfs (`cvmfs_config setup` is a handler).


Goal: only `login-node`, `nfs-server` and `slurm-master` stay up; compute
nodes are created when jobs are queued and deleted when idle. Decisions taken
with the user on 2026-09-18:

- **Suspend = delete the VM, resume = create a new one** (Slurm
  `SuspendProgram`/`ResumeProgram` on the slurm master, using the
  `slurm_master_course` app credential from #44, deployed as `clouds.yaml`).
  No shelve/stop.
- **No pre-created Neutron ports** — plain OpenStack DNS is enough. Measured
  on the dev cluster by replacing `slurm-worker-02` (new IP) while polling the
  tenant resolver `130.59.31.248` every 2 s: NXDOMAIN ~4 s after the VM was
  deleted, the new A record ~9 s after the new instance started creating, no
  stale IP and no cached NXDOMAIN; PTR records follow. Names are
  `<vm>.zhw.compute.local`, short names resolve via the DHCP search domain
  (Neutron `dns-integration`; Designate is not in the catalog). Fresh answers
  always carry TTL 3600.
- **Stop managing `/etc/hosts`**: set `slurm_install_manage_etc_hosts: false`
  (`group_vars/all/slurm.yml`). A replaced node otherwise keeps its old IP in
  every host's `/etc/hosts` (seen in the DNS test).
- **Disable the systemd-resolved cache** on `login-node`, `slurm-master` and
  `nfs-server` (`Cache=no`), so a re-created node's new IP is used at once.
- **Compute nodes boot from a pre-built image** built with the existing
  Ansible roles (users, NFS, CVMFS, R, munge, slurmd) and uploaded to Glance;
  in configless mode slurmd fetches its config from slurmctld
  (`slurmd --conf-server`), so the image carries no `slurm.conf`. Not a stock
  image configured at boot (too slow for `ResumeTimeout`).

Order of work:

1. **Collection first — configless mode** in `slurm_install`:
   `SlurmctldParameters=enable_configless`, slurmd with `--conf-server`,
   `sackd` on the login (submit) node, `/etc/hosts` management already
   optional (`slurm_install_manage_etc_hosts`). Verify in the collection's
   test setups first, then on a dev deploy.
2. **Collection — elastic scheduling**: cloud nodes (`State=CLOUD`),
   resume/suspend programs creating/deleting VMs via the OpenStack API,
   `SuspendTime`/`ResumeTimeout`, `clouds.yaml` on the controller. Check in
   the Slurm 25.11 docs whether slurmctld keeps its own address cache
   (`cloud_dns` and related `SlurmctldParameters`) before relying on DNS.
   The deleted `slurm.conf.course.j2` in git history is a (half-migrated)
   reference.
3. **Compute-node image script** (aux): build the image with Ansible, upload
   to Glance.
4. **This repo**: drop the static workers from `opentofu/`, set
   `slurm_install_manage_etc_hosts: false`, disable the resolved cache on the
   three permanent nodes, wire in the collection's new options and the app
   credential.

## Other next steps

1. Re-run speed (re-run ~4 min): the per-user loops in `configure.yml` take
   ~80 s (30 users × 5 loops; the three NFS-server-only loops could be one
   script task), and facts are gathered once per play (`gathering = smart` +
   jsonfile fact cache in `ansible.cfg`).
2. Move `slurm_install_dbd_storage_password` (still plaintext in
   `group_vars/all/slurm.yml`) to ansible-vault.
3. Consider declaring the course accounts/users with the collection's
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
- **Every host is reached through the login node** (ProxyCommand in
  `group_vars/all/ansible_ssh.yml`): rebooting it together with the others
  cut their tunnels mid-command, the reboot module took the drop for the
  reboot starting, and a worker timed out after 600 s without ever rebooting
  (#43 reboots the login node last). Keep this in mind for any task that
  restarts networking or sshd on the login node.
- **`/tmp` is per-node**; job output must go to `/shared/home/...` (NFS).
- **Application credentials are bound to one project**: adding `project_id`
  to `clouds.yaml` does not rescope them. The credential for this work is
  scoped to `SIB-Training #woVM`.
- **Creating the slurm master's app credential needs an unrestricted one**:
  `opentofu/slurm-master.tf` creates `slurm_master_course` (restricted) and
  writes it to the gitignored
  `ansible/inventory/group_vars/slurm_master/openstack_app_credential.yml`.
  Keystone refuses that request from a restricted application credential, so
  tofu must authenticate with an *unrestricted* one (or a user password/token).
- **A failed apply can orphan a security group** (Neutron 500 while deleting
  its default rules): the group exists in the cloud but not in the state, and
  the next apply fails with "Multiple security_group matches found". Delete
  the orphan (the one with no ports attached), then re-apply.
- **One state, no workspaces**: `dev.tfvars` and `prod.tfvars` produce the
  same VM names, so only one environment can exist at a time. Pass
  `-var ssh_key_name=<name>` when a keypair of the default name
  (`opentofu_key`) already exists in the project.
- **Changing the bootstrap key of a running cluster locks Ansible out**: the
  VMs only trust the key they booted with, and tofu replaces the keypair
  without replacing the VMs. `tofu destroy` first, then apply.
- **`astral-sh/setup-uv` has no moving major tags** since v8 (`@v10` fails to
  resolve); pin the full version.
- **`ansible-lint --offline` lints fewer files and fails** here; keep it
  online (it installs `requirements.yml` into `ansible/.ansible`).

## Dev environment: keep the venv off the shared mount

The clone lives on a Lima VM share (virtiofs since 2026-09-18, 9p before).
Creating a venv on it is ~35x slower than on the VM disk, measured with
`uv venv --no-cache` + `uv pip install --no-cache` of ansible-core, pytest and
ansible-lint (2,991 files, 54 MB): **~30 s on virtiofs vs ~0.8 s on ext4**. A
plain `cp -r` of that venv onto the share takes 28.5 s (0.07 s local), so the
cost is creating many small files over the share, not downloading. Lima has no
virtiofs cache setting (it starts `virtiofsd` with defaults).

- Keep the venv on the VM disk: `uv venv --python 3.12 /var/tmp/courses-venv`
  + `uv pip install -r ansible/requirements.txt` (~1 s), then use
  `/var/tmp/courses-venv/bin` on `PATH` (with `OS_CLOUD=openstack`).
- The same penalty hits anything writing many files into the repo
  (`ansible-galaxy install` into `ansible/roles`, `.terraform/`).
- `tofu` and `gh` are installed in `~/.local/bin` (release binaries). `gh`'s
  default token is refused by the `scicore-unibas-ch` org (fine-grained PAT
  lifetime > 366 days); use `GH_TOKEN=$(cat ~/.config/gh/scicore-courses-cloud.token)`
  for this repo. Git itself pushes over SSH (host alias
  `github-scicore-courses-cloud`, deploy key).
- `~/.config/openstack/clouds.yaml` (cloud `openstack`) holds an
  **unrestricted** app credential (`claude-course-dev-unrestricted`, expires
  2026-10-21), needed to create the slurm master's credential (#44).
- Ansible run from Claude's shell needs `</dev/null` (else "Ansible requires
  blocking IO on stdin/stdout/stderr").

## Conventions

- Work on a branch, open a PR, let CI (`Lint`: tofu fmt/validate +
  ansible-lint) pass; PRs are merged by the user, then the branch is deleted.
- Never run `tofu apply`/`destroy` without asking first — it creates billable
  cloud resources.
