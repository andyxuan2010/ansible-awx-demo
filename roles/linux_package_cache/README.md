# linux_package_cache role

Refreshes or cleans the package metadata cache on Debian-family and Red Hat-
family Linux systems. Both operations are disabled by default.

```bash
ansible-playbook playbooks/common/package_cache.yml \
  -l 'managed_nodes:&linux' \
  -e linux_package_cache_update=true
```

Run with `--check` first where supported and give the playbook a deliberate
limit. The role does not install, remove, or upgrade packages.
