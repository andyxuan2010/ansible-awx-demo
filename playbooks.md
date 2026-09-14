---
layout: default
title: Playbooks and usage
permalink: /playbooks.html
---

# Ansible playbooks

This repository is designed to run from the WSL Ubuntu control node and from
AWX. Run CLI commands from the repository root so `ansible.cfg` loads the
demo inventory and role path automatically. In AWX, select the matching
project, inventory, credentials, and limit in the job template instead of
passing interactive command-line options.

## Playbook layout

| Directory | Purpose |
|---|---|
| `playbooks/common/` | Cross-platform Linux and Windows operations |
| `playbooks/linux/` | Linux-only operations |
| `playbooks/windows/` | Windows-only operations |
| `playbooks/*.yml` | Compatibility entry points retained for existing AWX templates and CLI commands |

The root compatibility files import their categorized implementation. New
work should use the categorized path; existing AWX templates can continue to
use their current root path.

## Roles

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

## Targeting and AWX compatibility

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

## Common cross-platform playbooks

There are 46 common playbooks. Each contains separate Linux and Windows plays
and can be run against a site, group, or host limit.

### Baseline and operations

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

### Diagnostics and inventory

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

## Common command examples

### Inspect a site or host

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

### Run an explicitly enabled change

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

### Scheduled task examples

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

## Linux-specific playbooks

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

### SSH access audit

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

### Exposed Ubuntu hardening

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

## Windows-specific playbooks

| Playbook | Purpose | Typical command |
|---|---|---|
| `windows/ping.yml` | Test Windows connectivity | `ansible-playbook playbooks/windows/ping.yml -l windows` |
| `windows/packaging.yml` | Manage Windows packages | `ansible-playbook playbooks/windows/packaging.yml -l windows` |
| `windows/enable_win_sshd.yml` | Enable Windows OpenSSH | `ansible-playbook playbooks/windows/enable_win_sshd.yml -l windows` |

The root `windows_ping.yml`, `windows_packaging.yml`, and
`enable_win_sshd.yml` files remain compatibility imports for existing AWX
templates.

## Other compatibility entry points

| Root path | Canonical implementation or purpose |
|---|---|
| `playbooks/baseline.yml` | Imports `common/baseline.yml` and supports both platforms |
| `playbooks/ping.yml` | Imports the common connectivity playbook |
| `playbooks/sys-info.yml` | Imports the common system facts playbook |

## Validation before an AWX project sync

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
