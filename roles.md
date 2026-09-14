---
layout: default
title: Roles
permalink: /roles.html
---

# Ansible roles

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

## Role conventions

- Put safe, reusable defaults in `defaults/main.yml`.
- Keep implementation in `tasks/main.yml`; use templates for generated files.
- Add `meta/main.yml` with the supported Ansible version and dependencies.
- Keep site- and host-specific values in inventory variables or AWX surveys.
- Change-oriented roles should expose an explicit opt-in variable or be used
  only by a playbook that clearly represents the change.
- Do not store passwords, private keys, or vault passphrases in a role.

## Safe role example

Run the read-only demo role from WSL:

```bash
ansible-playbook playbooks/examples/role_demo.yml -l site_b
```

In AWX, create a job template using the project and production inventory,
attach the appropriate Machine credential, and use the Limit field for the
site or host. The demo role does not modify managed hosts.

## Exposed Ubuntu hardening

`exposed_ubuntu_hardening` is deliberately disabled by default. It is scoped
to the Ubuntu aliases for demo-ubuntu-02 and demo-ubuntu-01 and their wireless SSH aliases. Use
the playbook's limit to pilot one physical node first, then explicitly set
`exposed_ubuntu_hardening_apply=true`. Review the SSH and firewall settings
before enabling it in production; password authentication is not disabled by
default to reduce lockout risk.

## Additional roles

`common_asset_report` and `windows_update_audit` are read-only reporting roles.
`linux_package_cache` is opt-in and does nothing unless its update or cleanup
variable is explicitly enabled. Keep change-oriented roles behind a deliberate
limit and review them in check mode first.
