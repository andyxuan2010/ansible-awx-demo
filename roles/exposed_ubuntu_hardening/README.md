# exposed_ubuntu_hardening role

This role provides an intentionally scoped hardening baseline for the Ubuntu
endpoints represented by `demo-ubuntu-02` and `demo-ubuntu-01`, including their wireless SSH
aliases. It is not a general Linux baseline.

The role is disabled by default. When explicitly enabled, it can install and
configure UFW, Fail2ban, and unattended security updates, harden selected SSH
daemon settings, and optionally disable SSH password authentication.

## Important safety behavior

- Set `exposed_ubuntu_hardening_apply=true` to make changes.
- The role allows the inventory-selected `ansible_port` on `tailscale0` before
  enabling UFW; override `exposed_ubuntu_hardening_ufw_interface` only when
  the overlay interface has a different name.
- SSH configuration is managed as a drop-in under `/etc/ssh/sshd_config.d/`
  and validated with `sshd -t` before the SSH handler runs. A failed change is
  restored automatically.
- Password authentication remains enabled unless
  `exposed_ubuntu_hardening_disable_password_authentication=true` is set.
- The playbook runs with `serial: 1` because the wireless and primary aliases
  can represent the same physical host.

## Main variables

- `exposed_ubuntu_hardening_enable_ufw`: defaults to `true`.
- `exposed_ubuntu_hardening_allowed_node_ids`: defaults to `demo-ubuntu-02` and
  `demo-ubuntu-01`; the role refuses other node IDs.
- `exposed_ubuntu_hardening_packages`: UFW, Fail2ban, and unattended upgrades.
- `exposed_ubuntu_hardening_ssh_settings`: SSH directives to enforce in the
  managed drop-in.
- `exposed_ubuntu_hardening_ssh_port`: defaults to the inventory `ansible_port`
  or port 22.
- `exposed_ubuntu_hardening_fail2ban_bantime`: defaults to `1h`.
- `exposed_ubuntu_hardening_fail2ban_findtime`: defaults to `10m`.
- `exposed_ubuntu_hardening_fail2ban_maxretry`: defaults to `5`.

## Tags

The playbook and role are tagged `security`, `hardening`, and
`exposed_ubuntu`. Fine-grained task tags are also available:

- `validation`: endpoint and Tailscale interface checks; safety checks use
  `always`.
- `packages`: install UFW, Fail2ban, and unattended-upgrades.
- `ssh`: apply SSH daemon settings.
- `firewall`: configure and enable UFW.
- `fail2ban`: configure Fail2ban.
- `updates`: configure unattended security updates.

Run the complete role for the first rollout. Use fine-grained tags for
reviewed follow-up changes, because a partial run assumes prerequisite
packages are already installed:

```bash
ansible-playbook playbooks/linux/exposed_ubuntu_hardening.yml \
  -l 'demo-ubuntu-02,demo-ubuntu-02-wireless' \
  -e exposed_ubuntu_hardening_apply=true \
  --tags firewall --ask-become-pass
```
