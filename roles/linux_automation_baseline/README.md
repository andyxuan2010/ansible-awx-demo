# linux_automation_baseline role

Installs a configurable set of Linux packages and creates the directory used
for local automation artifacts. The role is intended for Linux plays and is
used by `playbooks/common/baseline.yml`.

## Defaults

- `linux_automation_baseline_packages`: `git` and `curl`
- `linux_automation_baseline_directory`: `/opt/automation`
- `linux_automation_baseline_owner`: `root`
- `linux_automation_baseline_group`: `root`
- `linux_automation_baseline_mode`: `0755`

Override these values in inventory or an AWX extra-variable/survey definition.
