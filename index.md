---
layout: default
title: Ansible AWX Demo
home: true
---

<section class="section-intro" id="guides">
  <div>
    <p class="section-kicker">Documentation library</p>
    <h2>Choose your path</h2>
    <p>Use the guides below to move from a safe local example to a controlled AWX workflow.</p>
  </div>
</section>

<div class="guide-grid">
  <a class="guide-card guide-card-blue" href="awx.html">
    <span class="guide-icon">↗</span>
    <strong>AWX integration</strong>
    <span>Projects, inventories, execution environments, credentials, job templates, and approvals.</span>
    <b>Read the guide <span aria-hidden="true">→</span></b>
  </a>
  <a class="guide-card guide-card-teal" href="inventory.html">
    <span class="guide-icon">◇</span>
    <strong>Inventory design</strong>
    <span>Safe sample hosts, group hierarchy, targeting intersections, and SCM inventory sources.</span>
    <b>Explore inventory <span aria-hidden="true">→</span></b>
  </a>
  <a class="guide-card guide-card-purple" href="playbooks.html">
    <span class="guide-icon">▦</span>
    <strong>Playbooks &amp; usage</strong>
    <span>Common, Linux, Windows, and role-based examples with deliberate change controls.</span>
    <b>Browse playbooks <span aria-hidden="true">→</span></b>
  </a>
  <a class="guide-card guide-card-orange" href="https://github.com/andyxuan2010/ansible-awx-demo/blob/main/roles/README.md">
    <span class="guide-icon">⌘</span>
    <strong>Reusable roles</strong>
    <span>Role conventions and safe examples for reporting, baselines, updates, and hardening.</span>
    <b>View roles <span aria-hidden="true">→</span></b>
  </a>
</div>

<section class="feature-grid" aria-label="Project highlights">
  <div class="feature-panel">
    <span class="feature-label">01 / Coverage</span>
    <h3>Linux + Windows</h3>
    <p>Cross-platform playbooks, platform groups, transport examples, and shared operational tasks.</p>
  </div>
  <div class="feature-panel">
    <span class="feature-label">02 / Safety</span>
    <h3>Public-safe by design</h3>
    <p>Documentation-only addresses, sanitized names, no Vault material, and CI secret scanning.</p>
  </div>
  <div class="feature-panel">
    <span class="feature-label">03 / Operations</span>
    <h3>AWX-ready</h3>
    <p>SCM sync, execution environments, credentials, limits, surveys, workflows, and approvals.</p>
  </div>
</section>

This is a sanitized, public-safe Ansible project for learning cross-platform
playbooks, reusable roles, inventory design, and AWX workflows.

The repository is generated from a private source project. It uses
documentation-only hosts and contains no production credentials, Vault files,
private keys, or confidential infrastructure data.

## What is included

- Cross-platform Ansible playbooks for Linux and Windows.
- A normalized sample inventory using documentation-only addresses.
- Reusable roles for reporting, baselines, package caching, updates, and hardening demonstrations.
- AWX guidance for SCM projects, execution environments, credentials, surveys, limits, and approval-controlled changes.
- CI checks for inventory resolution, syntax, linting, smoke tests, and secret scanning.

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt -r requirements-dev.txt
ansible-galaxy collection install -r requirements.yml
ansible-inventory -i inventory/production/hosts.yml --graph
ansible-playbook -i inventory/production/hosts.yml playbooks/common/asset_report.yml -l managed_nodes
```

The sample inventory is intentionally non-routable. Use a private inventory
and AWX credentials before connecting to real hosts.

## Project links

- [View the source repository](https://github.com/andyxuan2010/ansible-management)
- [View the generated public repository](https://github.com/andyxuan2010/ansible-awx-demo)
- [About this demo](ABOUT.html)
