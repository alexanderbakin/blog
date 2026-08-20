---
title: "Exposing a Homelab to the Internet Without Exposing Myself"
slug: "homelab-zero-trust"
date: 2022-06-12T00:00:00Z
draft: false
tags:
  - Tailscale
  - Authentik
  - Zero Trust
  - Homelab
  - Security
categories:
  - Homelab
---

Once the homelab had more than one service worth using away from home (Nextcloud for files, Jellyfin for media), "just port forward it" stopped being an option I was willing to consider. I spend enough of my working hours dealing with what happens to services that sit on the open internet unpatched or misconfigured for a week. I wasn't going to do that to my own network.

## Layer One: A Private Network That Doesn't Need Open Ports

Tailscale solved the "I want access from anywhere" problem without opening a single inbound port on my router. It's WireGuard under the hood: every device gets a key, joins the same private tailnet, and talks to every other device directly (or through a relay when direct connection isn't possible) over an encrypted tunnel. My phone, laptop, and homelab nodes all land on the same private address space no matter which network they're actually sitting on. For anything only *I* need to reach, that's the entire solution: no public DNS record, no exposed port, nothing for an internet-wide scanner to ever find.

That covers me. It doesn't cover the two family members I wanted to share Jellyfin with, who were never going to install a VPN client to watch something.

## Layer Two: Authentication in Front of Anything Public

For the small number of services that genuinely needed a public entry point, I put Authentik in front of them as a forward-auth proxy. The pattern is straightforward: a reverse proxy (Traefik, in my case) has an `auth_request` style directive pointing at an Authentik outpost for any route that needs protecting. A request comes in, gets redirected to Authentik's login flow if there's no valid session, and only reaches the actual application once Authentik has said yes.

```yaml
labels:
  - "traefik.http.routers.jellyfin.middlewares=authentik@docker"
  - "traefik.http.middlewares.authentik.forwardauth.address=http://authentik-server:9000/outpost.goauthentik.io/auth/traefik"
  - "traefik.http.middlewares.authentik.forwardauth.trustForwardHeader=true"
```

This gets me proper accounts, optional 2FA, and a single place to revoke access, instead of sharing a Jellyfin password over text and hoping nobody reuses it somewhere worse.

## Splitting the Blast Radius

The part I think matters more than either tool individually is the decision about which services get a public listener at all. Only Jellyfin and Nextcloud, both sitting behind Authentik, ever get a public DNS record. Everything else, Vaultwarden included, stays Tailscale-only and has never had a public-facing listener in its life. If Authentik itself or the reverse proxy in front of it is ever compromised, the number of services actually reachable from that foothold is two, not everything I run. That's the same principle behind not giving a CI pipeline's deploy credentials access to every environment it doesn't need: least exposure by default, and a public listener has to earn its way onto that list, not start there.

## Watching the Front Door

A public Authentik login page is now the actual attack surface of my homelab, so it's the thing I watch most closely. Authentik's logs ship to Loki alongside everything else, and a simple LogQL query counting failed logins per source IP over a short window feeds an Alertmanager rule: more than a handful of failures in five minutes pages me. It hasn't fired for anything more exciting than me forgetting my own password, but the day it fires for something else, I want to know within minutes, not find out from a support ticket.

## Lessons

- **A VPN and a public auth gateway solve different problems.** Tailscale is for devices you control. A forward-auth proxy is for people you don't want to hand a VPN client to.
- **Decide what's public deliberately, not by default.** Every service should start Tailscale-only. Public exposure is an explicit, reviewed decision, not the default state.
- **Whatever you do expose becomes your highest-value target.** Monitor it accordingly, from day one, not after the first incident.
