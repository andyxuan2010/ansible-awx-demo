# windows_management_marker role

Creates a Windows management directory and writes a marker containing site,
node, hostname, and operating-system metadata. It is used by the Windows play
in `playbooks/common/baseline.yml`.

## Defaults

- `windows_management_marker_enabled`: `true`
- `windows_management_marker_directory`: `C:\ProgramData\AnsibleManagement`
- `windows_management_marker_path`: `C:\ProgramData\AnsibleManagement\managed-by.txt`

Set `windows_management_marker_enabled: false` when a host should not receive
the marker.
