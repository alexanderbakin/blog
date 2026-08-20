---
title: "Deploying Vaultwarden with Ansible: My Homelab's First Real Service"
slug: "vaultwarden-ansible"
date: 2021-07-18T00:00:00Z
draft: false
tags:
  - Ansible
  - Homelab
  - Self-Hosting
  - Vaultwarden
  - Linux
categories:
  - Homelab
---

I started self-hosting for a boring reason: I didn't like that a single cloud account breach could hand someone every password I own. A self-hosted password manager has its own risks, but at least the blast radius is mine to control. Vaultwarden (a lightweight Bitwarden-compatible server) was the obvious first service, and I used it as an excuse to do my homelab properly instead of SSH-ing in and running commands by hand.

## Why Not Just a Shell Script

At work I manage Linux servers with Ansible, and the reason is the same at home as it is there: idempotency. A shell script that installs Docker, pulls an image, and starts a container works fine the first time. Run it again after you've tweaked something manually, and it either fails halfway or silently does the wrong thing. An Ansible playbook run against a host that's already in the desired state does nothing. Run it against a host that's drifted, and it fixes exactly the drift and nothing else.

That property matters more at home than you'd expect, because a homelab is where you *will* SSH in at 11pm and hand-edit something to fix an immediate problem. The playbook is what puts the host back on the rails afterward.

## The Role

The Vaultwarden role is small: install Docker, template an environment file, define the container.

```yaml
- name: Ensure Vaultwarden data directory exists
  ansible.builtin.file:
    path: /opt/vaultwarden
    state: directory
    mode: "0750"

- name: Template Vaultwarden environment file
  ansible.builtin.template:
    src: vaultwarden.env.j2
    dest: /opt/vaultwarden/.env
    mode: "0600"
  notify: restart vaultwarden

- name: Run Vaultwarden container
  community.docker.docker_container:
    name: vaultwarden
    image: "vaultwarden/server:{{ vaultwarden_version }}"
    env_file: /opt/vaultwarden/.env
    ports:
      - "127.0.0.1:8000:80"
    volumes:
      - /opt/vaultwarden/data:/data
    restart_policy: unless-stopped
```

Notice the port binding: `127.0.0.1:8000`, not `0.0.0.0`. Vaultwarden never talks to the internet directly. A reverse proxy in front of it terminates TLS and is the only thing that ever sees a public network interface.

The `ADMIN_TOKEN` and SMTP credentials live in the templated `.env` file, which is itself rendered from a variable encrypted with `ansible-vault`. That means the entire homelab configuration, secrets included, lives in a private git repo and can be applied to a brand new host with one command, without a single value typed in by hand at deploy time.

## Monitoring From Day One

It's tempting to skip monitoring on a "just a homelab" service and add it later once something breaks. I didn't want to build that habit, because it's the same habit that causes outages at work. So from the first deploy, every host runs `node_exporter` and `cadvisor`, logs ship to Loki via Promtail, and there's a single Grafana dashboard per host showing container health and resource usage. Alertmanager routes a "container down" or "disk over 85%" alert to a webhook on my phone. It's a fraction of the observability stack I run in production, but the shape is identical: metrics, logs, and alerts, not just a service quietly running until it isn't.

## What I'd Do Differently

The SQLite database backing Vaultwarden lives on exactly one disk, on exactly one machine, in my apartment. A nightly `sqlite3 .backup` to encrypted off-site storage was the very next thing I automated, and it should have been part of the same playbook run instead of an afterthought a week later. Getting a service running is easy. Making its failure modes boring is the actual job, and that's true whether it's a homelab container or something with a 99.9% SLA.
