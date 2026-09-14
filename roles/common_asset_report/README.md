# common_asset_report role

Read-only role that displays normalized host metadata for Linux and Windows.
It is useful for an AWX demonstration, inventory review, or a small audit job.
It does not modify the managed host.

```yaml
- hosts: managed_nodes
  gather_facts: true
  roles:
    - common_asset_report
```

The role intentionally reports connection metadata but never prints passwords,
private keys, or other credential variables.
