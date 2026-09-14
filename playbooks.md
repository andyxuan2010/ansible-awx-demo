# Playbooks and usage

The public snapshot contains current cross-platform, Linux, Windows, and role
examples from the source repository. Change-oriented jobs should use a
deliberate Limit, check mode where supported, and AWX credentials.

## Common playbooks

| Playbook | Purpose |
|---|---|
| admin_group_audit.yml | Common Linux/Windows example |
| asset_report.yml | Common Linux/Windows example |
| baseline.yml | Common Linux/Windows example |
| config_backup.yml | Common Linux/Windows example |
| connectivity.yml | Common Linux/Windows example |
| directory.yml | Common Linux/Windows example |
| disk_usage.yml | Common Linux/Windows example |
| dns_lookup.yml | Common Linux/Windows example |
| ensure_service.yml | Common Linux/Windows example |
| environment.yml | Common Linux/Windows example |
| file_checksum.yml | Common Linux/Windows example |
| filesystem_health.yml | Common Linux/Windows example |
| firewall_status.yml | Common Linux/Windows example |
| http_check.yml | Common Linux/Windows example |
| identity.yml | Common Linux/Windows example |
| install_common_tools.yml | Common Linux/Windows example |
| installed_software.yml | Common Linux/Windows example |
| listening_ports.yml | Common Linux/Windows example |
| local_accounts.yml | Common Linux/Windows example |
| log_summary.yml | Common Linux/Windows example |
| management_marker.yml | Common Linux/Windows example |
| mounts.yml | Common Linux/Windows example |
| network_config.yml | Common Linux/Windows example |
| package_cache.yml | Common Linux/Windows example |
| patch_systems.yml | Common Linux/Windows example |
| pending_updates.yml | Common Linux/Windows example |
| port_check.yml | Common Linux/Windows example |
| process_control.yml | Common Linux/Windows example |
| process_summary.yml | Common Linux/Windows example |
| reboot_required.yml | Common Linux/Windows example |
| reboot_systems.yml | Common Linux/Windows example |
| resource_usage.yml | Common Linux/Windows example |
| route_table.yml | Common Linux/Windows example |
| runtime.yml | Common Linux/Windows example |
| scheduled_task.yml | Common Linux/Windows example |
| scheduled_task_status.yml | Common Linux/Windows example |
| security_status.yml | Common Linux/Windows example |
| service_inventory.yml | Common Linux/Windows example |
| service_status.yml | Common Linux/Windows example |
| shares.yml | Common Linux/Windows example |
| ssh_access_audit.yml | Common Linux/Windows example |
| system_facts.yml | Common Linux/Windows example |
| temp_cleanup.yml | Common Linux/Windows example |
| time_sync.yml | Common Linux/Windows example |
| timezone.yml | Common Linux/Windows example |
| uptime.yml | Common Linux/Windows example |

Example commands:

    ansible-playbook playbooks/common/connectivity.yml -l managed_nodes
    ansible-playbook playbooks/common/asset_report.yml -l managed_nodes
    ansible-playbook playbooks/common/baseline.yml -l managed_nodes:&linux --check

See awx.md for Project, inventory, Execution Environment, credential, Vault,
Job Template, and Workflow integration guidance.
