# Public demo inventory

This inventory is a normalized template. It uses documentation-only addresses
and generic aliases; replace it in a private project before operational use.

The hierarchy separates location (sites), operational scope (managed_nodes),
platform (linux, windows, esxi, macos), services, hardware, and deferred/status
groups. A host can belong to several dimensions. Use intersections such as
managed_nodes:&site_b:&windows when selecting a platform within a site.

Duplicate endpoint aliases demonstrate a shared node_id. Ansible still treats
each alias as a separate host, so avoid targeting both aliases for a change
unless that is intentional.

    ansible-inventory --graph
    python scripts/validate_inventory.py
