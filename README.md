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

- AWX integration guide: awx.md
- Inventory guide: inventory.md
- Playbooks and usage: playbooks.md
- Roles: roles/README.md
