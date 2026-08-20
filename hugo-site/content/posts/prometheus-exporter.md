---
title: "Writing a Prometheus Exporter in Go for Metrics Nobody Was Collecting"
slug: "prometheus-exporter"
date: 2023-08-21T00:00:00Z
draft: false
tags:
  - Prometheus
  - Go
  - Observability
  - Monitoring
  - WAF
categories:
  - Observability
---

The platform I operate is a fleet of NGINX instances running a Web Application Firewall module in front of production traffic. The stock NGINX exporter gave us request counts, status codes, and upstream latency, all useful, and all completely blind to the one question that actually mattered for this platform: is the WAF itself doing its job, or is it about to fall over.

## The Gap

The WAF module exposes its own internal counters through a local status endpoint: rule hits, rule blocks broken down by rule ID, requests evaluated per second, memory used by the rule engine. None of it reaches Prometheus by default, because it's not something the generic NGINX exporter knows exists. Our dashboards could tell us "NGINX is up." They couldn't tell us "rule 942100 just started blocking forty times its normal traffic," which is exactly the kind of thing that means either an attack is underway or a rule update just went sideways and started blocking legitimate users. Both are pages. Neither showed up anywhere.

## Why a Purpose-Built Exporter, Not a Log Pipeline

The obvious alternative was parsing the WAF's log output and shipping counts through the existing Loki pipeline. I considered it and rejected it: logs are for investigating an incident after you know something's wrong. What I needed was a number I could graph and alert on in real time, and the WAF module already exposed that number on a local status endpoint. Writing an exporter that scrapes it and reshapes it into Prometheus's format is a much smaller, much more honest piece of software than a log-parsing pipeline pretending to be a metrics system.

## The Exporter

Go was the right tool mostly for boring reasons: it compiles to a static binary with no runtime to install on production boxes that are already carrying enough software, and `client_golang` (Prometheus's own instrumentation library) makes exposing metrics almost mechanical.

```go
var ruleBlocks = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "waf_rule_blocks_total",
        Help: "Total requests blocked, labeled by rule ID.",
    },
    []string{"rule_id"},
)

func scrapeWAFStatus(url string) error {
    resp, err := http.Get(url)
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    var status WAFStatus
    if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
        return err
    }
    for _, rule := range status.Rules {
        ruleBlocks.WithLabelValues(rule.ID).Add(float64(rule.Blocks))
    }
    return nil
}

func main() {
    prometheus.MustRegister(ruleBlocks)
    go pollLoop(*statusURL, *interval)
    http.Handle("/metrics", promhttp.Handler())
    log.Fatal(http.ListenAndServe(*listenAddr, nil))
}
```

Trimmed for length, but that's the whole shape of it: poll the status endpoint on an interval, translate its counters into Prometheus vectors, serve `/metrics`. Under two hundred lines including flag parsing and error handling.

## Alerting on What Actually Matters

With per-rule metrics in Prometheus, the alerts got specific instead of generic. Beyond the usual "upstream down" class of alert, we added rules like a per-rule block rate more than a set number of standard deviations above its own 24-hour baseline, which catches both a genuine attack spike and a bad rule update in the same signal, and leaves the on-call engineer to tell which is which from context instead of finding out from a customer first. That single exporter ended up backing around twenty of the alerts on that platform, covering everything from individual rule anomalies to overall engine health.

## Rollout

The exporter shipped through the same Ansible role that deploys the rest of the WAF stack: a templated systemd unit, a Prometheus `scrape_config` entry added to the same commit, nothing bespoke about how it got to production. Consistency in *how* things get deployed matters as much as what gets deployed.

## Lessons

- **Instrument what the business actually cares about**, not just what the framework hands you for free. Generic exporters get you uptime. Custom ones get you the metric that would have caught the actual incident.
- **A small purpose-built binary beats a clever log pipeline** for anything you want to alert on in real time.
- **Give every exporter its own dashboard**, not just a panel buried in a generic host dashboard, or the signal gets lost in the noise it was supposed to cut through.
