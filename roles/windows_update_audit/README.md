# windows_update_audit role

Read-only Windows update audit using `Get-HotFix`. It reports the most recent
hotfixes and how many fall within the configured audit window.

The role does not install updates or reboot the host. Configure
`windows_update_audit_days` and `windows_update_audit_limit` as needed.
