---
title: "Getting to 99.9%: Kubernetes and Real Observability for 20+ Microservices"
slug: "k8s-observability"
date: 2025-09-15T00:00:00Z
draft: false
tags:
  - Kubernetes
  - Prometheus
  - Grafana
  - Loki
  - SRE
categories:
  - Kubernetes
---

99.9% availability sounds like a slogan until you do the arithmetic: it's a budget of roughly eight and a half hours of downtime for an entire year, across every service on the platform. Once you frame it that way, it stops being an aspiration and becomes an engineering constraint you either design for or blow through by month three. Getting there for a platform of 20+ microservices took deliberate work in two places that don't get enough credit next to "just add more replicas": the rollout path, and observability that's actually fast enough to matter.

## Availability Isn't One Thing

Most of the downtime we were losing wasn't outages in the dramatic sense. It was smaller and more mundane: a rollout sending traffic to a pod before it was actually ready to serve it, a routine node drain during a cluster upgrade taking out every replica of a service at once because nothing stopped it, resource limits set from guesswork causing OOMKills the moment traffic spiked above whatever number someone picked at design time. None of these show up as "the cluster is down." All of them show up in an availability number.

## Fixing the Rollout Path

Every service got readiness and liveness probes tuned to what that specific service actually needs to be considered healthy, not a copy-pasted `/healthz` with a five-second timeout regardless of what the service does. PodDisruptionBudgets ensure a voluntary disruption (a node drain, a cluster upgrade) can't take every replica of a service down at once, which sounds obvious once it's said and was silently absent everywhere before. Topology spread constraints keep replicas of the same service off the same node and, where the node pool spans zones, off the same zone, so a single node or zone failure degrades a service instead of eliminating it.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout-api
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: checkout-api
```

## Terraform for the Platform Itself

Node pools, IAM roles for service accounts, DNS records, and cluster add-ons all live in Terraform, not clicked into existence in a console. That's not just tidiness. When something asks "which availability zone is that node pool actually in," there's one source of truth instead of a guess and a login. And standing up a second cluster for disaster recovery testing is a `terraform apply` against a new workspace, not a week of manually reconstructing what the first one happened to end up looking like after two years of ad hoc changes.

## The Observability Stack

Metrics come from Prometheus, scraping `kube-state-metrics` and `node_exporter` cluster-wide plus a `/metrics` endpoint per service. Grafana is the single pane of glass for dashboards. Logs ship through Promtail running as a DaemonSet into Loki. Alertmanager handles routing and dedup.

The part that actually moved the needle on how fast we detect problems wasn't adding more dashboards, it was wiring metrics and logs together in the same place. A Grafana panel showing a service's error rate links directly, through shared labels, to that service's logs in Loki for the exact time window the spike happened. Before that, an on-call engineer seeing an alert had to go find the right service, then `kubectl logs` across however many pods it happened to be running, hoping the failing one hadn't already been replaced by the deployment's own self-healing. After, the alert and the explanation are two clicks apart in the same tool. That mechanism, not raw alert volume, is what cut mean time to detect from around thirty minutes to five.

## Alerting That Doesn't Cry Wolf

Flat thresholds like "page if error rate exceeds 1%" either fire on noise or stay silent while real budget burns slowly. We moved critical services to multi-window burn-rate alerts tied to the actual SLO: a fast-burn window catches a sharp spike before it eats the whole monthly error budget, a slow-burn window catches a smaller but sustained degradation that a short window would miss entirely. Alerts stopped being about crossing an arbitrary number and started being about whether the error budget was actually at risk.

## Result

99.9% measured availability across the platform, and mean time to detect down from roughly thirty minutes to five.

## Lessons

- **Availability is a property of the whole system**, rollout behavior and scheduling constraints included, not just a replica count.
- **Terraform the platform, not just the workloads running on it.** The infrastructure underneath Kubernetes needs the same discipline as what's deployed to it.
- **An alert that isn't actionable within your MTTD budget isn't observability, it's noise with extra steps.** Wiring metrics to logs in the same tool did more for detection speed than any single dashboard.
