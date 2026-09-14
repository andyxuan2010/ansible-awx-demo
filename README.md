# Public Ansible AWX demo

This repository is an automatically generated, sanitized demonstration of the
private Ansible management project. It is intended for learning Ansible CLI
and AWX integration patterns, not for managing real systems.

The inventory uses documentation-only 192.0.2.0/24 addresses and .example
names. It contains no production hosts, Vault files, passwords, private keys,
scan output, or confidential infrastructure data.

## Start here

    python3 -m venv .venv
    source .venv/bin/activate
    python -m pip install -r requirements.txt -r requirements-dev.txt
    ansible-galaxy collection install -r requirements.yml
    ansible-inventory --graph
    ansible-playbook playbooks/common/asset_report.yml -l managed_nodes

Use a private inventory and AWX Credentials before connecting to real hosts.
The public repository intentionally cannot reach or authenticate to the demo
addresses.

The complete guides are included below for a single-page reference and are
also kept as separate Markdown files for direct linking and maintenance.

- AWX integration guide: awx.md
- Inventory guide: inventory.md
- Playbooks and usage: playbooks.md
- Roles: roles/README.md

## AWX integration guide

This document describes how to integrate this repository with AWX while
keeping the Ansible CLI workflow working. The repository is designed around a
Git-controlled project, a static YAML inventory, reusable roles, explicit
platform targeting, and credentials injected by AWX at job launch.

### 1. Architecture

```mermaid
flowchart LR
    GIT[Git repository<br/>playbooks, roles, inventory] --> PROJECT[AWX Project<br/>SCM sync]
    PROJECT --> EE[Execution Environment<br/>ansible-runner]
    INV[AWX Inventory<br/>SCM inventory source] --> JT[Job Template]
    PROJECT --> JT
    EE --> JT
    CREDS[AWX Credentials<br/>Machine, Vault, become] --> JT
    JT --> RUN[Execution node<br/>/runner/project]
    RUN --> SSH[Linux / ESXi<br/>SSH]
    RUN --> WIN[Windows<br/>WinRM or SSH]
```

AWX does not run Ansible from the administrator's WSL session. A job runs in
an AWX execution environment on an execution node. The execution node must
have network reachability to the managed hosts, the required collections and
Python libraries, and the credentials supplied to the job.

The repository contributes content and configuration. AWX contributes runtime
selection, secrets, RBAC, scheduling, logging, and execution placement.

### 2. Repository contract

The important integration points are:

| Repository item | AWX use |
|---|---|
| `ansible.cfg` | Default inventory, role path, SSH behavior, and Ansible defaults |
| `inventory/production/hosts.yml` | SCM inventory source path |
| `inventory/production/group_vars/` | Site, platform, and shared variables |
| `playbooks/` | Job Template playbook choices |
| `roles/` | Roles available through `roles_path` |
| `requirements.yml` | Required Ansible collections for the execution environment |
| `requirements.txt` | Local control-node dependencies and EE Python dependency reference |
| `.github/workflows/ansible-ci.yml` | Pre-merge and post-commit quality gates |
| `vault/site_a.yml`, `vault/site_b.yml` | Encrypted site variables loaded explicitly by selected playbooks |

The repository's standard inventory is configured as:

```ini
[defaults]
inventory = ./inventory/production/hosts.yml
roles_path = ./roles
```

AWX normally runs with `/runner/project` as the project working directory, so
the relative paths resolve when the Project content is present. For maximum
predictability, select the inventory explicitly in the AWX Inventory and keep
the Job Template tied to the same Project revision.

### 3. Create the AWX Project

In AWX, create a Project with:

| Field | Recommended value |
|---|---|
| Name | `ansible-management` |
| Organization | The owning organization |
| Source Control Type | Git |
| Source Control URL | The repository's HTTPS or SSH clone URL |
| Source Control Branch/Tag | `main`, or a controlled release branch/tag |
| Source Control Credential | Only if the repository is private |
| Update Revision on Launch | Enabled for development; use controlled syncs for production |
| Cache Timeout | Short enough for required updates, long enough to avoid unnecessary syncs |

Use a deploy key or a GitHub App/token with read-only repository access for a
private project. Do not place a Git token in a playbook, survey, inventory, or
extra variable.

After saving, run **Sync** and confirm the project revision. A successful
Project sync proves that AWX received the repository; it does not prove that
the execution environment can reach any managed host.

### 4. Build or select the Execution Environment

An Execution Environment (EE) is the container image used as the Ansible
control node for a job. It must contain the Ansible version, collections, and
Python libraries used by this repository.

This repository currently declares:

```yaml
# requirements.yml
ansible.windows==3.7.0
community.windows==3.3.0
chocolatey.chocolatey==1.6.0
```

and Python dependencies including:

```text
ansible-core==2.19.13
pywinrm==0.5.0
```

For production, build and pin a custom EE rather than relying on a mutable
`latest` image. The EE should include:

1. The pinned collections from `requirements.yml`.
2. `pywinrm` for Windows WinRM connections.
3. Kerberos dependencies only when Kerberos is actually used.
4. The same Ansible core major/minor version tested by CI.
5. Any system packages required by scripts or lookup plugins.

Select the pinned EE in every production Job Template. Updating an EE should
be a versioned change tested against the repository before rollout.

### 5. Create and sync the AWX Inventory

Create an AWX Inventory, then add an **Inventory Source** with:

| Field | Value |
|---|---|
| Source | Project |
| Project | The project created above |
| Inventory file | `inventory/production/hosts.yml` |
| Update on Launch | Enabled when inventory changes must be picked up automatically |
| Cache timeout | Appropriate for the operational change rate |

Run **Update** and verify the expected `all`, `sites`, `managed_nodes`,
`platform`, `services`, and deferred/status groups.

The inventory deliberately separates dimensions:

- `sites` describes location.
- `managed_nodes` is the normal operational scope and contains all four sites.
- `platform` contains `linux`, `windows`, `esxi`, and `macos` branches.
- `linux` contains the distribution groups, and `redhat` contains version groups.
- `services` describes roles such as `truenas`, `nfs_servers`, and hypervisors.
- `observations`, `nonssh`, and `ansible_unreachable` are excluded from normal
  managed scope.

Use intersections in playbooks and Limits, for example:

```text
managed_nodes:&site_b:&windows
managed_nodes:&linux
managed_nodes:&site_c
```

Do not create a second manually maintained AWX inventory that duplicates this
SCM inventory unless there is a clear ownership boundary. Duplicate inventory
definitions are a common source of stale connection variables.

### 6. Credentials and secret flow

#### Machine credentials

Create the appropriate AWX Machine credential for the target transport:

- Linux and ESXi SSH: username, SSH private key, and optional become settings.
- Windows WinRM: username and password, with inventory selecting
  `ansible_connection: winrm` and the WinRM port/transport.
- Windows OpenSSH: username and SSH private key, with inventory selecting
  `ansible_connection: ssh` and the Windows SSH shell settings.

The credential is injected into the job's isolated runtime. AWX does not
inherit the SSH key from `/root/.ssh/`, a developer's Windows profile, or a
separate WSL session.

#### Vault credentials

The site Vault files are intentionally outside `inventory/production/group_vars`:

```text
vault/site_a.yml
vault/site_b.yml
```

The Windows plays that need them load them explicitly with play-level
`vars_files`. The encrypted files contain their own Vault ID labels. Create one
AWX Vault credential per label, using the exact matching Vault ID, and attach
the required credentials to the Job Template:

| Credential | Purpose |
|---|---|
| `machine-linux` | SSH key and Linux account |
| `machine-windows` | WinRM or Windows SSH account |
| `vault-site-a` | Decrypts `vault/site_a.yml` |
| `vault-site-b` | Decrypts `vault/site_b.yml` |
| Machine become settings | Privilege escalation when required |

For jobs that can parse or target both sites, attach both Vault credentials.
For a site-scoped job, attach at least the Vault credential required by every
playbook play AWX will parse. Never pass a Vault password through a survey or
`extra_vars`.

An AWX SCM inventory source cannot be expected to decrypt arbitrary Vault files
without a credential. Keeping encrypted files out of `group_vars` prevents an
inventory synchronization failure such as:

```text
ERROR! Attempting to decrypt but no vault secrets found
```

The Vault credential belongs on the Job Template or Workflow node, while the
playbook owns the explicit file path. This keeps inventory import independent
of runtime secret access.

#### Secret-handling rules

- Never commit plaintext passwords, private keys, tokens, or Vault password files.
- Do not put secrets in surveys, defaults, hostnames, comments, or debug output.
- Use `no_log: true` around tasks that may process sensitive values.
- Do not print `ansible-inventory --list` output when secret variables are loaded.
- Rotate any credential that was exposed, even if the containing commit is later
  deleted.
- Limit credential visibility by organization, team, and Job Template RBAC.

### 7. Job Template design

Create separate Job Templates for different risk and credential boundaries.
Recommended initial templates are:

| Job Template | Playbook | Limit | Mode |
|---|---|---|---|
| Connectivity | `playbooks/common/connectivity.yml` | Required at launch | Read-only |
| Asset report | `playbooks/common/asset_report.yml` | `managed_nodes` or site | Read-only |
| SSH access audit | `playbooks/common/ssh_access_audit.yml` | Site/platform | Read-only |
| Linux baseline | `playbooks/common/baseline.yml` | `managed_nodes:&linux` | Controlled change |
| Linux updates | `playbooks/linux/update_linux.yml` | Small canary first | Controlled change |
| Windows baseline | `playbooks/common/baseline.yml` | `managed_nodes:&windows` | Controlled change |
| Exposed Ubuntu hardening | `playbooks/linux/exposed_ubuntu_hardening.yml` | One node first | High risk, opt-in |

Configure each template with:

- Project and inventory from the same environment.
- A pinned Execution Environment.
- The minimum required Machine and Vault credentials.
- A required Limit for change-oriented jobs.
- A reasonable fork/concurrency limit.
- Job slicing only when the playbook is safe to parallelize.
- Verbosity normally `0`; increase it temporarily for troubleshooting.
- Notifications for failure, approval, and completion as appropriate.
- A timeout that prevents a stuck job from running indefinitely.

Use Workflows when a process has stages, for example:

```text
connectivity -> read-only audit -> approval -> canary update -> wider update
```

Do not make a production update template silently reboot all hosts. Reboot
should be a separate approval-controlled stage or require an explicit variable
such as `confirm_reboot=true`.

### 8. Surveys and extra variables

Surveys are appropriate for safe operational choices, not secret storage. Good
survey fields include:

```text
limit                  site or host pattern
apply_changes          boolean, default false
apply_updates          boolean, default false
confirm_reboot         boolean, default false
patch_serial           integer with a safe maximum
```

Use the template's Limit field for target selection when possible. Validate
survey choices and avoid exposing arbitrary module arguments. Extra vars have
high precedence, so an unrestricted survey can override inventory and role
defaults unexpectedly.

### 9. Transport implementation in this repository

#### Linux and ESXi

Linux plays use intersections such as:

```yaml
hosts: "managed_nodes:&linux"
```

The default SSH user is configured in `ansible.cfg` and inventory variables,
but the AWX Machine credential should be the authoritative source for the
private key. Linux change playbooks that use `become: true` require a credential
with privilege escalation configured.

#### Windows WinRM

Windows groups define the connection plugin and transport settings in
`inventory/production/group_vars/`:

```yaml
ansible_connection: winrm
ansible_port: 5985
ansible_winrm_transport: ntlm
```

The effective user and password must come from the AWX Machine credential or a
private Vault variable. A WinRM port combined with `ansible_connection: ssh`
causes errors such as “Connection closed ... port 5985.” After changing group
variables, sync the Project and update the AWX Inventory before rerunning the
Job Template.

#### Windows OpenSSH

OpenSSH is a separate transport. Use `ansible_connection: ssh`, the SSH port,
the appropriate `ansible_shell_type`, and a Machine credential containing the
private key. Do not attach an SSH key and expect it to authenticate a WinRM
connection.

### 10. CLI and AWX parity

The CLI equivalent of an AWX job should be reproducible from the repository
root:

```bash
ansible-inventory --graph
ansible managed_nodes --list-hosts
ansible-playbook playbooks/common/connectivity.yml -l site_b \
  --vault-id site_a@prompt --vault-id site_b@prompt
ansible-playbook playbooks/common/asset_report.yml -l managed_nodes
ansible-playbook playbooks/linux/update_linux.yml \
  -l 'managed_nodes:&linux' --check
```

In AWX, translate these options as follows:

| CLI option | AWX setting |
|---|---|
| `-i` | Inventory selection |
| Playbook path | Job Template Playbook |
| `-l` | Job Template Limit or survey field |
| `--vault-id` | Attached Vault credential with matching ID |
| `--ask-become-pass` | Machine credential privilege escalation settings |
| `-e name=value` | Template extra vars or validated survey field |
| `--check` | Check-mode option or a dedicated check template |
| `--tags` / `--skip-tags` | Job Template Options fields |

Do not put shell command-line options into the playbook path. For example,
`demo_b_redhat9` after the playbook name is interpreted as another playbook; use `-l demo_b_redhat9`
for a host limit.

### 11. CI and release workflow

The repository workflow should pass before an AWX Project sync is promoted:

1. Pull request review.
2. YAML and inventory validation.
3. Playbook syntax checks.
4. Safe role smoke tests.
5. Target-resolution checks.
6. YAML and Ansible lint.
7. Secret scanning.
8. Merge to the controlled branch.
9. AWX Project sync and inventory update.
10. Read-only connectivity/audit job.
11. Approval-controlled change workflow.

Pin collection, Python, Ansible, and EE versions. Test the exact EE image used
by production AWX; a local WSL installation is not an equivalent runtime.

### 12. RBAC and operating model

Use separate AWX teams or roles for project/inventory administrators, credential
administrators, read-only auditors, operators who can launch change jobs, and
production approvers.

Grant users access to Job Templates instead of broad credential access when
possible. Keep production and lab inventories separate, restrict who can edit
surveys and extra vars, and record changes through Git and AWX activity logs.

For high-impact roles, use a dedicated template with a narrow Limit, serial
execution, approval, and an explicit opt-in variable. The
`exposed_ubuntu_hardening` role is an example of this pattern.

### 13. Publishing a sanitized public snapshot

The repository includes `.github/workflows/publish-awx-demo.yml` for publishing
the current source snapshot to a separate public repository. Its default target
is `andyxuan2010/ansible-awx-demo`; a workflow-dispatch input can override the
target repository.

The workflow has two jobs:

1. `build-and-validate` checks out the source, runs
   `scripts/publish_awx_demo.py`, generates normalized demo inventory and
   documentation, scans for Vault/key/private-network data, and runs inventory,
   syntax, YAML-lint, and Ansible-lint checks.
2. `publish` waits on the `public-demo-publish` protected environment, then
   creates the destination repository if needed and pushes the sanitized
   snapshot to its `main` branch.

The generated snapshot excludes `old/`, `vault/`, production inventory and
group variables, bootstrap scripts, source-specific documentation, and the
publisher workflow itself. It uses documentation-only addresses and generic
aliases. The source repository remains the system of record; the public repo
is a generated artifact and should not be edited manually.

#### One-time GitHub configuration

1. Create the public destination repository, or allow the workflow token to
   create it.
2. Add a repository secret named `AWX_DEMO_REPO_TOKEN`. Use a GitHub App or a
   fine-grained token with only the permissions needed to create/update the
   destination repository. Do not use a personal credential in workflow YAML.
3. Create the `public-demo-publish` Environment and configure required
   reviewers. The build job runs first; the publish job pauses for approval.
4. Optionally define the repository variable `AWX_DEMO_REPO` to override the
   default target. A manual workflow run can also supply `target_repo`.
5. Push to `main` or run the workflow manually. Review the build artifact before
   approving publication.

The sanitizer is a defense-in-depth control, not a substitute for review. Add
new exclusion or normalization rules whenever a new secret-bearing file,
private endpoint format, or environment-specific naming convention is added.

### 14. Troubleshooting checklist

#### Inventory update fails with a Vault error

Check that encrypted files are not under `inventory/production/group_vars`.
The inventory source must parse without a Vault credential. Put the files in
`vault/`, load them with play-level `vars_files`, attach matching Vault
credentials to the Job Template, and resync the inventory.

#### Linux reports `Permission denied (publickey)`

Confirm the AWX Machine credential contains the correct private key and user.
Validate from the AWX execution node or a matching EE, not only from WSL. Check
that the Job Template actually has the credential attached and that a stale
inventory variable is not overriding `ansible_user` or `ansible_host`.

#### Windows reports a connection closed on port 5985

Inspect the resolved inventory variables and confirm:

```yaml
ansible_connection: winrm
ansible_port: 5985
```

Then verify that the Windows Machine credential supplies the account and
password, the execution node can reach the port, and the Project/Inventory
were resynchronized after the variable change.

#### Collection or module is unavailable

Inspect the selected EE. Install the pinned collections from `requirements.yml`
inside the EE and select that image in the Job Template. Project sync alone is
not a substitute for building the runtime dependencies.

#### A playbook targets zero hosts

Run `ansible-inventory --graph` locally and inspect the AWX Inventory Hosts and
Groups pages. Check spelling and intersections such as
`managed_nodes:&linux`. A host may be in a site group but outside
`managed_nodes`, `windows`, or `linux`.

### 15. Production readiness checklist

- [ ] Project points to the intended repository, branch, and revision.
- [ ] Inventory source is `inventory/production/hosts.yml`.
- [ ] Inventory update succeeds without decrypting Vault files.
- [ ] The selected EE is pinned and contains all collections and Python libs.
- [ ] Execution nodes can reach SSH, WinRM, DNS, and any required proxy path.
- [ ] Machine credentials are attached and scoped correctly.
- [ ] Required Vault credentials are attached to the Job Template or Workflow.
- [ ] No passwords or private keys are in Git, surveys, or extra vars.
- [ ] Connectivity and read-only audit jobs pass first.
- [ ] Change jobs require a deliberate Limit and safe defaults.
- [ ] Reboots and hardening jobs have approval or a separate controlled stage.
- [ ] AWX RBAC and notifications are configured.
- [ ] CI passed for the exact commit and EE used for the launch.

### References

- [AWX job templates](https://ansible.readthedocs.io/projects/awx/en/24.6.1/userguide/job_templates.html)
- [AWX credentials](https://ansible.readthedocs.io/projects/awx/en/24.6.1/userguide/credentials.html)
- [AWX execution environments](https://ansible.readthedocs.io/projects/awx/en/24.6.1/userguide/execution_environments.html)
- [AWX SCM inventory sources](https://ansible.readthedocs.io/projects/awx/en/24.6.1/administration/scm-inv-source.html)
- [AWX multiple credential assignment](https://ansible.readthedocs.io/projects/awx/en/24.6.1/administration/multi-creds-assignment.html)
- [Ansible inventory guide](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
- [Ansible Runner project and inventory layout](https://ansible.readthedocs.io/projects/runner/en/stable/intro.html)

## Inventory guide

This inventory is a normalized template. It uses documentation-only addresses
and generic aliases; replace it in a private project before operational use.

The hierarchy separates location (sites), operational scope (managed_nodes),
platform (linux, windows, esxi, macos), services, hardware, and deferred/status
groups. A host can belong to several dimensions. Use intersections such as
managed_nodes:&site_b:&windows when selecting a platform within a site.

Duplicate endpoint aliases demonstrate a shared node_id. Ansible still treats
each alias as a separate host, so avoid targeting both aliases for a change
unless that is intentional.

    ansible-inventory --graph
    python scripts/validate_inventory.py

## Playbooks and usage

## Ansible playbooks

This repository is designed to run from the WSL Ubuntu control node and from
AWX. Run CLI commands from the repository root so `ansible.cfg` loads the
demo inventory and role path automatically. In AWX, select the matching
project, inventory, credentials, and limit in the job template instead of
passing interactive command-line options.

### Playbook layout

| Directory | Purpose |
|---|---|
| `playbooks/common/` | Cross-platform Linux and Windows operations |
| `playbooks/linux/` | Linux-only operations |
| `playbooks/windows/` | Windows-only operations |
| `playbooks/*.yml` | Compatibility entry points retained for existing AWX templates and CLI commands |

The root compatibility files import their categorized implementation. New
work should use the categorized path; existing AWX templates can continue to
use their current root path.

### Roles

The reusable roles live in [`roles/`](roles.html). The cross-platform
baseline composes the existing `baseline` role with
`linux_automation_baseline` for Linux and `windows_management_marker` for
Windows. The read-only `awx_demo_report` role is available through
`playbooks/examples/role_demo.yml` for testing an AWX project and credential
without making host changes.

The `exposed_ubuntu_hardening` role is a separate, opt-in security baseline for
the less-trusted demo-ubuntu-02 and demo-ubuntu-01 environment. It is not included in the
general Linux baseline.

Additional reusable roles include `common_asset_report` for normalized
cross-platform reporting, `linux_package_cache` for opt-in package metadata
maintenance, and `windows_update_audit` for read-only hotfix reporting.

### Targeting and AWX compatibility

Most common playbooks use two plays with these selectors:

```yaml
hosts: "managed_nodes:&linux"
hosts: "managed_nodes:&windows"
```

This lets one job template target a site containing both operating systems.
For example, `-l site_b` selects both Linux and Windows members of `site_b`,
while the Linux play skips Windows and the Windows play skips Linux.

`common/connectivity.yml` is the exception: its Windows checks are split into
site-specific plays so each play can load the matching encrypted file from
`vault/` before opening a WinRM connection.

AWX recommendations:

- Store SSH, WinRM, become, and vault secrets in AWX Credentials. Do not add
  passwords or vault passphrases to survey defaults or extra variables.
- AWX SCM inventory sources cannot attach Vault credentials. Keep encrypted
  files outside `inventory/production/group_vars`; load them with play-level
  `vars_files` and attach the matching Vault credential to the Job Template.
- Use a Project sync before running the job so AWX receives the current commit.
- Set the inventory to the demo inventory and use the job template
  Limit field for `site_a`, `site_b`, `site_c`, `site_d`, or a host name.
- Expose only the required boolean or string variables through a survey.
  Change-oriented playbooks default to safe no-op behavior.
- Use job-template verbosity for troubleshooting rather than changing the
  repository playbook.
- Keep `--ask-become-pass`, `--vault-id`, and other interactive CLI options
  out of AWX templates; configure equivalent credentials in AWX.

### Common cross-platform playbooks

There are 46 common playbooks. Each contains separate Linux and Windows plays
and can be run against a site, group, or host limit.

#### Baseline and operations

| Playbook | Default behavior | Important variables |
|---|---|---|
| `common/baseline.yml` | Applies the Linux/Windows management baseline | None; Linux installs Git/curl and creates `/opt/automation` |
| `common/connectivity.yml` | Pings Linux and Windows hosts; loads the site-specific Vault before Windows checks | `--vault-id site_a@prompt`, `--vault-id site_b@prompt` for CLI runs |
| `common/asset_report.yml` | Reports normalized asset metadata through a reusable role | None |
| `common/listening_ports.yml` | Reports Linux and Windows listening sockets | None |
| `common/route_table.yml` | Reports Linux and Windows route tables | None |
| `common/package_cache.yml` | Performs opt-in Linux package metadata-cache maintenance | `linux_package_cache_update`, `linux_package_cache_clean` |
| `common/patch_systems.yml` | Patches both platforms with explicit opt-in and controlled rollout | `apply_updates=true`, `patch_serial`, `patch_reboot_after_updates` |
| `common/reboot_systems.yml` | Reports that reboot is disabled | `confirm_reboot=true` |
| `common/reboot_required.yml` | Reports pending reboot indicators | None |
| `common/management_marker.yml` | Writes management markers | Run only when marker changes are intended |
| `common/install_common_tools.yml` | Reports that installation is disabled | `apply_changes=true`, `linux_common_packages` |
| `common/ensure_service.yml` | Reports that service changes are disabled | `apply_changes=true`, service variables |
| `common/timezone.yml` | Reports the current timezone | `apply_changes=true`, `timezone_name` |
| `common/directory.yml` | Reports that directory changes are disabled | `apply_changes=true`, `managed_directory_path` |
| `common/temp_cleanup.yml` | Audits old temporary files | `apply_changes=true`, age/path variables |
| `common/scheduled_task.yml` | Reports that schedule changes are disabled | `apply_changes=true`, command/schedule variables |
| `common/process_control.yml` | Audits a named process | `process_name`, `apply_changes=true` to stop it |
| `common/config_backup.yml` | Reports that backup is disabled | `create_backup=true`, source/destination variables |

#### Diagnostics and inventory

| Playbook | Purpose | Important variables |
|---|---|---|
| `common/system_facts.yml` | Reports OS, hostname, kernel, and IP facts | None |
| `common/ssh_access_audit.yml` | Read-only audit of Linux and Windows SSH service, port 22, the `ansible` account, and authorized keys | `ansible-playbook playbooks/common/ssh_access_audit.yml -l managed_nodes` |
| `common/disk_usage.yml` | Reports filesystem usage | None |
| `common/filesystem_health.yml` | Reports filesystem free space and health | `filesystem_warning_percent` |
| `common/mounts.yml` | Reports mounts and Windows volumes | None |
| `common/network_config.yml` | Reports addresses and routes | None |
| `common/dns_lookup.yml` | Resolves a DNS name on each managed host | `dns_lookup_name` |
| `common/port_check.yml` | Checks a TCP port from each managed host | `check_host`, `check_port`, `check_timeout` |
| `common/http_check.yml` | Checks an HTTP endpoint from each managed host | `healthcheck_url`, `healthcheck_timeout` |
| `common/uptime.yml` | Reports uptime and last boot | None |
| `common/resource_usage.yml` | Reports CPU, memory, and load | None |
| `common/process_summary.yml` | Reports top processes | None |
| `common/service_status.yml` | Inspects one requested service | `linux_service_name`, `windows_service_name` |
| `common/service_inventory.yml` | Inventories all services | None |
| `common/firewall_status.yml` | Reports firewall state | None |
| `common/time_sync.yml` | Reports time synchronization | None |
| `common/installed_software.yml` | Reports installed software | None |
| `common/pending_updates.yml` | Checks available updates | None |
| `common/scheduled_task_status.yml` | Reports systemd timers and Windows tasks | None |
| `common/environment.yml` | Reports environment variables | None |
| `common/identity.yml` | Reports execution identity and admin status | None |
| `common/runtime.yml` | Reports Python, PowerShell, and runtime details | None |
| `common/file_checksum.yml` | Reports a SHA-256 checksum | `checksum_path` |
| `common/local_accounts.yml` | Audits local accounts | None |
| `common/admin_group_audit.yml` | Audits administrator group membership | `linux_admin_groups` |
| `common/log_summary.yml` | Collects recent warning/system logs | None |
| `common/security_status.yml` | Reports basic security status | None |
| `common/shares.yml` | Reports NFS/SMB mounts and Windows shares | None |

### Common command examples

#### Inspect a site or host

```bash
ansible-playbook playbooks/common/connectivity.yml -l site_b \\
  --vault-id site_b@prompt
ansible-playbook playbooks/common/system_facts.yml -l demo_b_redhat9
ansible-playbook playbooks/common/disk_usage.yml -l managed_nodes
ansible-playbook playbooks/common/dns_lookup.yml -l site_a -e dns_lookup_name=dns.example
ansible-playbook playbooks/common/port_check.yml -l site_b -e check_host=192.0.2.10 -e check_port=22
ansible-playbook playbooks/common/http_check.yml -l site_b -e healthcheck_url=https://example.com
ansible-playbook playbooks/common/runtime.yml -l base
ansible-playbook playbooks/common/reboot_required.yml -l site_b
ansible-playbook playbooks/examples/role_demo.yml -l site_b
```

#### Run an explicitly enabled change

```bash
ansible-playbook playbooks/common/patch_systems.yml -l site_b -e apply_updates=true
ansible-playbook playbooks/common/patch_systems.yml -l site_b -e apply_updates=true -e patch_reboot_after_updates=true
ansible-playbook playbooks/common/reboot_systems.yml -l site_b -e confirm_reboot=true
ansible-playbook playbooks/common/install_common_tools.yml -l site_a -e apply_changes=true
ansible-playbook playbooks/common/ensure_service.yml -l site_b -e apply_changes=true -e ensure_service_name=sshd
ansible-playbook playbooks/common/timezone.yml -l site_b -e apply_changes=true -e timezone_name=UTC
ansible-playbook playbooks/common/directory.yml -l site_b -e apply_changes=true -e managed_directory_path=/opt/shared
ansible-playbook playbooks/common/temp_cleanup.yml -l site_b -e apply_changes=true
ansible-playbook playbooks/common/process_control.yml -l site_b -e process_name=example -e apply_changes=true
ansible-playbook playbooks/common/config_backup.yml -l site_b -e create_backup=true
```

For Linux CLI changes that require privilege escalation, add
`--ask-become-pass` when the credential is not already configured. In AWX,
attach a Machine credential with the become option enabled instead.

Patching uses `serial: 1`, stops the play on an error with
`any_errors_fatal: true`, and does not reboot by default. Set
`patch_reboot_after_updates=true` only when the maintenance window permits a
reboot. `patch_serial` can be increased after a staged rollout; use a small
batch size for production. The reboot timeout and pre/post reboot delays are
also configurable through `patch_reboot_timeout`, `patch_reboot_pre_delay`,
and `patch_reboot_post_delay`.

#### Scheduled task examples

The scheduled-task playbook expects a command and is disabled unless explicitly
enabled:

```bash
ansible-playbook playbooks/common/scheduled_task.yml -l site_b \
  -e apply_changes=true \
  -e scheduled_task_command='/usr/local/sbin/health-check.sh'
```

For AWX, expose `apply_changes`, `scheduled_task_command`, and the schedule
variables as survey fields. Use an approved command and restrict the survey to
the operators who manage scheduled jobs.

### Linux-specific playbooks

| Playbook | Purpose | Typical command |
|---|---|---|
| `linux/baseline.yml` | Linux-only legacy baseline implementation | `ansible-playbook playbooks/linux/baseline.yml -l linux` |
| `linux/site.yml` | Linux site baseline role | `ansible-playbook playbooks/linux/site.yml -l site_b --ask-become-pass` |
| `linux/update_linux.yml` | Update Linux packages with serial/fail-fast rollout controls | `ansible-playbook playbooks/linux/update_linux.yml -l linux --ask-become-pass` |
| `linux/install_fail2ban.yml` | Install/configure Fail2ban | `ansible-playbook playbooks/linux/install_fail2ban.yml -l linux --ask-become-pass` |
| `linux/install_net_tools.yml` | Install Linux network tools | `ansible-playbook playbooks/linux/install_net_tools.yml -l ubuntu --ask-become-pass` |
| `linux/exposed_ubuntu_hardening.yml` | Harden demo-ubuntu-02/demo-ubuntu-01 Ubuntu endpoints with UFW, Fail2ban, unattended upgrades, and selected SSH settings | `ansible-playbook playbooks/linux/exposed_ubuntu_hardening.yml -l 'demo-ubuntu-02,demo-ubuntu-02-wireless' -e exposed_ubuntu_hardening_apply=true --ask-become-pass` |

The root `site.yml`, `update_linux.yml`, `install_fail2ban.yml`, and
`install_net_tools.yml` files remain compatibility imports for existing AWX
templates.

#### SSH access audit

The SSH access audit is read-only. It reports whether an SSH service is enabled
and running, whether TCP port 22 is listening, whether user `ansible` exists,
and whether that account has usable entries in `authorized_keys`. Linux hosts
are checked through SSH. Windows hosts are checked through their configured
WinRM connection and inspect both the per-user and administrator OpenSSH key
locations. A successful run authenticated as `ansible` confirms the credentials
used for that run can access the host as that user; a WinRM run does not by
itself prove that SSH authentication works.

```bash
ansible-playbook playbooks/common/ssh_access_audit.yml -l linux
ansible-playbook playbooks/common/ssh_access_audit.yml -l windows \\
  --vault-id site_a@prompt --vault-id site_b@prompt
```

To compare a specific controller-side public key with the remote
`authorized_keys`, provide its public `.pub` file on the CLI control node:

```bash
ansible-playbook playbooks/common/ssh_access_audit.yml -l managed_nodes \\
  -e ssh_audit_public_key_file="$HOME/.ssh/id_ed25519.pub"
```

Leave `ssh_audit_public_key_file` empty in AWX. AWX keeps the Machine
credential private key inside the execution environment, so the audit instead
confirms the authenticated remote user and the remote authorized-key file.

#### Exposed Ubuntu hardening

Audit the target and verify connectivity first:

```bash
ansible-playbook playbooks/linux/exposed_ubuntu_hardening.yml -l 'demo-ubuntu-02,demo-ubuntu-02-wireless'
ansible-playbook playbooks/linux/exposed_ubuntu_hardening.yml -l 'demo-ubuntu-01,demo-ubuntu-01-wireless'
```

Apply the role to one physical node at a time during the initial rollout:

```bash
ansible-playbook playbooks/linux/exposed_ubuntu_hardening.yml \
  -l 'demo-ubuntu-02,demo-ubuntu-02-wireless' -e exposed_ubuntu_hardening_apply=true --ask-become-pass
ansible-playbook playbooks/linux/exposed_ubuntu_hardening.yml \
  -l 'demo-ubuntu-01,demo-ubuntu-01-wireless' -e exposed_ubuntu_hardening_apply=true --ask-become-pass
```

The normal play target is `site_c:site_d:&ubuntu`, which includes the primary
and wireless aliases. It runs with `serial: 1` because aliases can represent
the same physical endpoint. The role verifies `tailscale0` and opens the
inventory-selected SSH port on that interface before enabling UFW, validates
`sshd_config` before restarting SSH, and keeps
password authentication enabled unless
`exposed_ubuntu_hardening_disable_password_authentication=true` is explicitly
provided. A conservative first AWX rollout should use a Limit of `demo-ubuntu-02` or
`demo-ubuntu-01`, attach the Machine credential with become enabled, and expose
`exposed_ubuntu_hardening_apply` as a survey boolean. Do not put SSH keys,
passwords, or vault passphrases in extra variables. The playbook supports the
fine-grained tags `validation`, `packages`, `ssh`, `firewall`, `fail2ban`, and
`updates`; use the complete role for the first rollout and tags only for
reviewed follow-up changes.

### Windows-specific playbooks

| Playbook | Purpose | Typical command |
|---|---|---|
| `windows/ping.yml` | Test Windows connectivity | `ansible-playbook playbooks/windows/ping.yml -l windows` |
| `windows/packaging.yml` | Manage Windows packages | `ansible-playbook playbooks/windows/packaging.yml -l windows` |
| `windows/enable_win_sshd.yml` | Enable Windows OpenSSH | `ansible-playbook playbooks/windows/enable_win_sshd.yml -l windows` |

The root `windows_ping.yml`, `windows_packaging.yml`, and
`enable_win_sshd.yml` files remain compatibility imports for existing AWX
templates.

### Other compatibility entry points

| Root path | Canonical implementation or purpose |
|---|---|
| `playbooks/baseline.yml` | Imports `common/baseline.yml` and supports both platforms |
| `playbooks/ping.yml` | Imports the common connectivity playbook |
| `playbooks/sys-info.yml` | Imports the common system facts playbook |

### Validation before an AWX project sync

Run the same checks as CI from WSL:

```bash
python scripts/validate_inventory.py
yamllint -c .yamllint .
find playbooks -type f -name '*.yml' ! -path '*/tasks/*' -print -exec ansible-playbook -i inventory/production/hosts.yml {} --syntax-check \;
ansible-playbook -i localhost, tests/exposed_ubuntu_hardening_safe.yml --check
ansible-lint --offline playbooks/common playbooks/linux playbooks/windows roles tests
```

These checks validate parsing and policy only; they do not connect to or
modify managed hosts.

## Roles

Roles are reusable implementation units loaded from the repository's
`roles_path`. The playbook selects the target hosts and role variables; the
role owns its tasks, templates, defaults, and metadata.

| Role | Purpose | Used by |
|---|---|---|
| `baseline` | Linux management marker and optional baseline packages | `playbooks/common/baseline.yml`, `playbooks/linux/site.yml` |
| `linux_automation_baseline` | Installs Linux baseline packages and creates `/opt/automation` | `playbooks/common/baseline.yml` |
| `windows_management_marker` | Creates the Windows management marker | `playbooks/common/baseline.yml` |
| `awx_demo_report` | Read-only execution-context report for demonstrations | `playbooks/examples/role_demo.yml` |
| `exposed_ubuntu_hardening` | Opt-in UFW, Fail2ban, unattended-upgrades, and SSH hardening for demo-ubuntu-02/demo-ubuntu-01 | `playbooks/linux/exposed_ubuntu_hardening.yml` |
| `common_asset_report` | Read-only normalized asset metadata for Linux and Windows | `playbooks/common/asset_report.yml` |
| `linux_package_cache` | Opt-in package-cache refresh and cleanup for Linux | `playbooks/common/package_cache.yml` |
| `windows_update_audit` | Read-only Windows hotfix audit | Custom Windows maintenance play |

### Role conventions

- Put safe, reusable defaults in `defaults/main.yml`.
- Keep implementation in `tasks/main.yml`; use templates for generated files.
- Add `meta/main.yml` with the supported Ansible version and dependencies.
- Keep site- and host-specific values in inventory variables or AWX surveys.
- Change-oriented roles should expose an explicit opt-in variable or be used
  only by a playbook that clearly represents the change.
- Do not store passwords, private keys, or vault passphrases in a role.

### Safe role example

Run the read-only demo role from WSL:

```bash
ansible-playbook playbooks/examples/role_demo.yml -l site_b
```

In AWX, create a job template using the project and production inventory,
attach the appropriate Machine credential, and use the Limit field for the
site or host. The demo role does not modify managed hosts.

### Exposed Ubuntu hardening

`exposed_ubuntu_hardening` is deliberately disabled by default. It is scoped
to the Ubuntu aliases for demo-ubuntu-02 and demo-ubuntu-01 and their wireless SSH aliases. Use
the playbook's limit to pilot one physical node first, then explicitly set
`exposed_ubuntu_hardening_apply=true`. Review the SSH and firewall settings
before enabling it in production; password authentication is not disabled by
default to reduce lockout risk.

### Additional roles

`common_asset_report` and `windows_update_audit` are read-only reporting roles.
`linux_package_cache` is opt-in and does nothing unless its update or cleanup
variable is explicitly enabled. Keep change-oriented roles behind a deliberate
limit and review them in check mode first.
