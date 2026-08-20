---
title: "From 4 Hours to 20 Minutes: Replacing a Manual Deployment with GitLab CI"
slug: "faster-gitlab-ci"
date: 2024-04-09T00:00:00Z
draft: false
tags:
  - GitLab CI
  - CI/CD
  - Docker
  - DevOps
  - Automation
categories:
  - CI/CD
---

Deploying used to mean an engineer, a runbook document, and four hours of undivided attention. Not four hours of a pipeline running in the background, four hours of a person actively driving it: SSH into the target host, pull the latest code, run the build script by hand, stop the old process, start the new one, watch the logs to see if it came up clean, and post a status update. It worked, in the sense that it got code to production. It didn't scale, in the sense that "get code to production" now depended entirely on one specific person having a free afternoon.

## Why That Stops Working

The team wanted to ship more often. A four-hour manual process gated by a single person's calendar makes that structurally impossible, no matter how careful that person is. What actually happened in practice was releases getting bundled: instead of shipping a small change the day it was ready, changes queued up and got batched into one larger, riskier release to justify burning an afternoon on it. The manual process wasn't just slow, it was actively pushing the team toward bigger, scarier deploys, which is the opposite of what you want.

## Building the Pipeline, Not Speeding One Up

There was no existing CI/CD pipeline to optimize. The job was to take a process that lived in a runbook doc and a person's memory, and turn it into something that ran the same way every time whether or not that person was even online.

```yaml
stages: [build, test, deploy, verify]

build:
  stage: build
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

test:
  stage: test
  script: [npm test]

deploy:
  stage: deploy
  script:
    - ansible-playbook deploy.yml -e image_tag=$CI_COMMIT_SHORT_SHA
  environment: production

verify:
  stage: verify
  script: [./scripts/smoke-test.sh $PROD_URL]
```

Every stage here replaced a step someone used to do by hand. `build` replaced running a shell script on the target box directly against production, which meant the image now got built once, consistently, instead of "however the box happened to be configured that week." `deploy` replaced manually stopping and starting a process over SSH with an Ansible playbook that does the same thing, every time, without depending on which engineer remembers the exact sequence. `verify` replaced someone eyeballing the logs for a minute and deciding it looked fine.

## The Parts That Were Actually Scary to Automate

The easy 80% of this was mechanical: turn shell commands into CI script lines. The remaining 20% was the part that had been manual specifically because it was risky, and that's the part that mattered most to get right.

Database migrations had been run by hand, one at a time, with someone watching in case something needed a manual fix mid-way. Automating that meant first making migrations themselves safe to run unattended: idempotent, reversible, and separated from application deploys so a bad migration doesn't take the whole release down with it. Configuration had lived as manually-edited files sitting on each box, tweaked in place over time until nobody was fully sure what the real values were anymore; that moved into templated files driven by CI variables, so the deployed configuration matches what's in git, not whatever a box happened to accumulate. And rollback, which used to mean "someone fixes it live," became its own pipeline job that redeploys the last known-good image tag, so recovering from a bad release doesn't require the same person who found the problem to also be the one improvising a fix under pressure.

## Making Speed Safe

None of this is worth much if a twenty-minute automated pipeline just ships broken code faster than a four-hour manual one did. The `verify` stage's smoke tests against the live deploy, plus a deployment validation check before a release counts as complete, did more for confidence than the automation itself. That's the piece that made shipping multiple times a day feel safe rather than reckless, and it's a large part of why failed releases dropped by roughly half even as release frequency went up.

## Result

Four hours of one person's attention became twenty minutes of a pipeline running unattended, and multiple production releases in a single day went from a scheduling problem to routine.

## Lessons

- **The biggest CI/CD win often isn't making an existing pipeline faster, it's replacing a human runbook with one.** There was no pipeline to speed up here, only a process to automate.
- **Automating a manual process forces you to write down what actually happens**, and that surfaces gaps (unsafe migrations, drifted config) the manual process had been quietly working around.
- **Removing the "who's available to deploy today" bottleneck did more for release cadence than raw pipeline speed.** Twenty minutes matters, but not being gated on a specific person's calendar matters more.
- **Don't automate the happy path and leave the scary parts manual.** Migrations, config, and rollback were exactly the parts worth the most effort to get right.
