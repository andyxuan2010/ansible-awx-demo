# Playbook organization

Playbooks are grouped by purpose:

- `common/` contains cross-platform Linux and Windows tasks, including `baseline.yml`. Change-oriented playbooks are opt-in through variables such as `apply_changes=true` or `confirm_reboot=true`.
- `linux/` contains Linux-specific operations.
- `windows/` contains Windows-specific operations and transport-aware tasks.
- `examples/` contains safe demonstrations of reusable roles and AWX execution.
- YAML files directly under `playbooks/` are compatibility entry points for existing AWX job templates and CLI commands. New playbooks should be added to a purpose-based subdirectory.

The compatibility entry points import the implementation from its categorized directory, so existing paths such as `playbooks/site.yml` and `playbooks/baseline.yml` continue to work. The canonical cross-platform baseline is `common/baseline.yml`.

The complete playbook catalog, variables, CLI examples, and AWX job-template guidance is maintained in [`../playbooks.md`](../playbooks.md).
