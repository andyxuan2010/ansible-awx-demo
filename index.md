---
layout: default
title: Ansible AWX Demo
---

This is a sanitized, public-safe Ansible project for learning cross-platform
playbooks, reusable roles, inventory design, and AWX workflows.

The repository is generated from a private source project. It uses
documentation-only hosts and contains no production credentials, Vault files,
private keys, or confidential infrastructure data.

## Start here

Choose the path that matches what you want to review:

| Guide | What it covers |
| --- | --- |
| [AWX integration guide](awx.html) | Projects, inventories, execution environments, credentials, job templates, workflows, and publishing |
| [Inventory guide](inventory.html) | Safe sample inventory structure, groups, host targeting, and AWX inventory sources |
| [Playbooks and usage](playbooks.html) | Common, Linux, Windows, and role-based examples |
| [Roles](https://github.com/andyxuan2010/ansible-awx-demo/blob/main/roles/README.md) | Reusable role conventions and the safe demo role |

## What is included

- Cross-platform Ansible playbooks for Linux and Windows.
- A normalized sample inventory using documentation-only addresses.
- Reusable roles for reporting, baselines, package caching, updates, and hardening demonstrations.
- AWX guidance for SCM projects, execution environments, credentials, surveys, limits, and approval-controlled changes.
- CI checks for inventory resolution, syntax, linting, smoke tests, and secret scanning.

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt -r requirements-dev.txt
ansible-galaxy collection install -r requirements.yml
ansible-inventory -i inventory/production/hosts.yml --graph
ansible-playbook -i inventory/production/hosts.yml playbooks/common/asset_report.yml -l managed_nodes
```

The sample inventory is intentionally non-routable. Use a private inventory
and AWX credentials before connecting to real hosts.

## Project links

- [View the source repository](https://github.com/andyxuan2010/ansible-management)
- [View the generated public repository](https://github.com/andyxuan2010/ansible-awx-demo)
- [About this demo](ABOUT.html)
