# scicore-courses-cloud — Project Context

OpenTofu + Ansible for the sciCORE course clusters on the SWITCH OpenStack
cloud (region `zhw`). `opentofu/` boots the VMs, `ansible/` configures them;
hosts land in inventory groups from the VM tags (`inventory/openstack.yml`).

## Status (2026-09-18)

**Slurm now comes from the `pescobar.slurm` collection** (role
`slurm_install`, github.com/pescobar/ansible-collection-slurm, cloned at
`../ansible-collection-slurm`), replacing the old `scicore.slurm` role
(`../ansible-role-slurm`, reference only — do not modify it). PRs #29–#37
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
  (first run ~16 min, re-run ~4 min): a worker job sees `/cvmfs`; R 4.6.1
  loads the r2u CRAN/Bioconductor packages and `rstudio-server` answers on
  :8787; Open OnDemand serves `https://<fip-dashed>.sslip.io` with a Let's
  Encrypt cert and `user01` logs into the dashboard (PAM basic auth, default
  course password is in `group_vars/all/local_users.yml`). Launching a
  `bc_desktop` session was not tested.

**Idempotency (PRs #33, #34, #37):** the re-run still showed changes, now
fixed: `update_ood_portal` ran with `changed_when: true` and restarted apache
every run (now `--detailed-exitcodes --force`); the cvmfs presync shell tasks
(now `changed_when: false`); `r-base` installed before the r2u repo + pin, so
the next dist-upgrade swapped 15 `r-cran-*` packages (now installed after the
pin). A one-time `autoremove` of `networkd-dispatcher` on the second run is
expected. **#36 (ed25519 key) and #37 are not yet verified on real VMs** — the
next deploy should do two `site.yml` runs and expect `changed=0` on the second.

**Other changes 2026-09-18:** R packages install with one `apt` call per list
(#32); CI installs with `uv` + its cache instead of pip (lint job ~72 s →
~30 s), runs on `ubuntu-26.04`, `setup-opentofu@v2`, no ansible-lint warnings
(#35); the tofu bootstrap key is ed25519, `~/.ssh/id_ed25519_tofu` (#36).

## Next steps

1. Next deploy: run `site.yml` twice and confirm the second run is
   `changed=0` (verifies #36 and #37).
2. Re-run speed (second run ~4 min, not done yet): the per-user loops in
   `configure.yml` take ~80 s (30 users × 5 loops; the three NFS-server-only
   loops could be one script task), and facts are gathered once per play
   (`gathering = smart` + jsonfile fact cache in `ansible.cfg`).
3. Move `slurm_install_dbd_storage_password` (still plaintext in
   `group_vars/all/slurm.yml`) to ansible-vault.
4. Later, in the collection first: configless mode (`sackd` on the login
   node), then OpenStack elastic scheduling (resume/suspend programs,
   `clouds.yaml` on the controller, the commented-out app-credential
   resources in `opentofu/slurm-master.tf`), then an aux script to build
   compute-node images.
5. Consider declaring the course accounts/users with the collection's
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
- Ansible run from Claude's shell needs `</dev/null` (else "Ansible requires
  blocking IO on stdin/stdout/stderr").

## Conventions

- Work on a branch, open a PR, let CI (`Lint`: tofu fmt/validate +
  ansible-lint) pass; PRs are merged by the user, then the branch is deleted.
- Never run `tofu apply`/`destroy` without asking first — it creates billable
  cloud resources.
