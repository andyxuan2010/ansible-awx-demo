# baseline role

The baseline role is intentionally small. It can optionally install packages and writes a management marker containing site and node metadata.

## Variables

- `baseline_manage_marker`: enable or disable the marker; defaults to `true`.
- `baseline_packages`: list of packages to install; defaults to an empty list.
- `baseline_managed_marker_path`: directory for the marker; defaults to `/etc/ansible-management`.

Add additional roles beside `baseline` as the repository grows, and keep site- or node-specific values in inventory variable files rather than embedding them in playbooks.
