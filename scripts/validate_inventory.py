#!/usr/bin/env python3
"""Validate invariants for the hand-maintained production inventory."""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "inventory" / "production" / "hosts.yml"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def group_body(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def collect_groups(groups: dict, group_map: object) -> None:
    for name, value in group_body(group_map).items():
        body = group_body(value)
        existing = groups.setdefault(name, {})
        for key in ("hosts", "children", "vars"):
            if key in body:
                existing.setdefault(key, {})
                existing[key].update(group_body(body[key]))
        collect_groups(groups, body.get("children", {}))


def effective_hosts(groups: dict, name: str, seen: set[str] | None = None) -> set[str]:
    if name not in groups:
        fail(f"group {name!r} is not defined")

    seen = set() if seen is None else seen
    if name in seen:
        fail(f"group cycle detected at {name!r}")
    seen.add(name)

    body = groups[name]
    hosts = set(group_body(body.get("hosts", {})))
    for child in group_body(body.get("children", {})):
        hosts.update(effective_hosts(groups, child, seen.copy()))
    return hosts


def collect_endpoints(endpoint_map: dict, group_map: object) -> None:
    for value in group_body(group_map).values():
        body = group_body(value)
        for alias, host_vars in group_body(body.get("hosts", {})).items():
            if isinstance(host_vars, dict) and "ansible_host" in host_vars:
                endpoint = str(host_vars["ansible_host"])
                endpoint_map[endpoint][alias].add(host_vars.get("node_id"))
        collect_endpoints(endpoint_map, body.get("children", {}))


def validate() -> None:
    try:
        inventory = yaml.safe_load(INVENTORY.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        fail(f"cannot read {INVENTORY}: {exc}")

    if not isinstance(inventory, dict) or not isinstance(inventory.get("all"), dict):
        fail("inventory must define an 'all' group")

    groups = {"all": inventory["all"]}
    collect_groups(groups, inventory["all"].get("children", {}))

    required = {
        "sites",
        "managed_nodes",
        "site_a",
        "site_b",
        "site_c",
        "site_d",
        "platform",
        "linux",
        "redhat",
        "redhat7",
        "redhat8",
        "redhat9",
        "centos",
        "ubuntu",
        "debian",
        "linux_other",
        "windows",
        "site_a_windows",
        "site_b_windows",
        "truenas",
        "nfs_servers",
    }
    missing = sorted(required - groups.keys())
    if missing:
        fail(f"required groups are missing: {', '.join(missing)}")

    for parent in ("sites", "managed_nodes"):
        children = set(group_body(groups[parent].get("children", {})))
        expected = {"site_a", "site_b", "site_c", "site_d"}
        if children != expected:
            fail(f"{parent}.children must be {sorted(expected)}, found {sorted(children)}")

    linux_children = set(group_body(groups["linux"].get("children", {})))
    expected_linux_children = {
        "redhat",
        "centos",
        "ubuntu",
        "debian",
        "linux_other",
    }
    if linux_children != expected_linux_children:
        fail(
            "linux.children must be "
            f"{sorted(expected_linux_children)}, found {sorted(linux_children)}"
        )

    redhat_children = set(group_body(groups["redhat"].get("children", {})))
    expected_redhat_children = {"redhat7", "redhat8", "redhat9"}
    if redhat_children != expected_redhat_children:
        fail(
            "redhat.children must be "
            f"{sorted(expected_redhat_children)}, found {sorted(redhat_children)}"
        )

    distro_hosts = set()
    for group in ("redhat", "centos", "ubuntu", "debian", "linux_other"):
        hosts = effective_hosts(groups, group)
        distro_hosts.update(hosts)
        if not hosts <= effective_hosts(groups, "linux"):
            fail(f"{group} contains hosts outside linux")

    linux_hosts = effective_hosts(groups, "linux")
    if linux_hosts != distro_hosts:
        fail(
            "linux is not exactly the union of redhat, centos, ubuntu, debian, "
            "and linux_other"
        )

    if effective_hosts(groups, "sites") != effective_hosts(groups, "managed_nodes"):
        fail("sites and managed_nodes do not contain the same site hosts")

    truenas_hosts = effective_hosts(groups, "truenas")
    expected_truenas_hosts = {"nas", "nas2", "nfs"}
    if truenas_hosts != expected_truenas_hosts:
        fail(
            "truenas must contain "
            f"{sorted(expected_truenas_hosts)}, found {sorted(truenas_hosts)}"
        )
    if not truenas_hosts <= effective_hosts(groups, "site_b"):
        fail("truenas contains hosts outside site_b")

    nfs_server_hosts = effective_hosts(groups, "nfs_servers")
    if not truenas_hosts <= nfs_server_hosts or "storage" not in nfs_server_hosts:
        fail("nfs_servers must contain truenas and storage")

    windows_children = set(group_body(groups["windows"].get("children", {})))
    if windows_children != {"site_a_windows", "site_b_windows"}:
        fail("windows must contain site_a_windows and site_b_windows only")

    endpoint_map = defaultdict(lambda: defaultdict(set))
    collect_endpoints(endpoint_map, inventory["all"].get("children", {}))
    duplicate_endpoints = 0
    for endpoint, aliases in endpoint_map.items():
        if len(aliases) < 2:
            continue
        duplicate_endpoints += 1
        node_ids = set().union(*aliases.values())
        if None in node_ids or len(node_ids) != 1:
            fail(
                f"duplicate endpoint {endpoint!r} must have one shared node_id; "
                f"aliases={sorted(aliases)}, node_ids={sorted(str(x) for x in node_ids)}"
            )

    print(
        "Inventory invariants passed: "
        f"{len(effective_hosts(groups, 'all'))} unique aliases, "
        f"{len(linux_hosts)} Linux hosts, "
        f"{len(effective_hosts(groups, 'windows'))} Windows hosts, "
        f"{duplicate_endpoints} duplicate endpoint sets."
    )


if __name__ == "__main__":
    validate()
