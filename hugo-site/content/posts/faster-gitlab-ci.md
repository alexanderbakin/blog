---
title: "From 4 Hours to 20 Minutes: Rebuilding a GitLab CI Pipeline"
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

The pipeline I inherited took four hours from commit to something running in staging. One `.gitlab-ci.yml`, one long sequential path: lint, then the full test suite, then a Docker build from scratch, then deploy. One push queued behind whatever was already running, because there was effectively one lane for all of it. Four hours is long enough that "just push a fix" stops being a real option, and releases had settled into a once-a-week ritual instead of something that happened whenever code was ready.

## Diagnosing Where the Time Actually Went

I didn't start by guessing. GitLab's own pipeline analytics break down duration per job, and the picture was mundane rather than mysterious: the Docker build alone was taking twenty-five minutes because every layer rebuilt from scratch on every run, no cache pulled from anywhere. The test suite ran serially, with slow integration tests interleaved among fast unit tests instead of separated. And every job, regardless of what it depended on, waited its turn on a single shared runner.

None of that needed a rewrite. It needed the pipeline to stop doing unnecessary work and stop waiting on itself.

## Fix 1: Actually Use the Docker Layer Cache

The Dockerfile copied application code before installing dependencies, which meant every code change invalidated the dependency-install layer and forced a full reinstall. Reordering it so dependencies install against a lockfile copied in first, before the rest of the source, meant that layer only rebuilds when the lockfile changes.

```dockerfile
FROM node:20-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:20-slim
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
```

Combined with pulling the previous image tag at the start of the job and building with `--cache-from` against it, and a multi-stage build so the final image never carries the build toolchain, the build dropped to under five minutes and the resulting image shrank by roughly a third, which mattered again later for pull time on every deploy.

## Fix 2: Split the Waterfall

The default GitLab CI behavior runs stages strictly in sequence: everything in `test` waits for everything in `build` to finish, even jobs with no actual dependency on each other. Splitting the monolithic `test` stage into `unit` (fast, runs first, blocks the pipeline on failure) and `integration` (slower, runs in parallel across multiple runners), and rewriting dependencies with `needs:` instead of relying on stage order, let independent jobs run concurrently rather than queuing behind unrelated work.

```yaml
unit-tests:
  stage: test
  script: [npm run test:unit]

integration-tests:
  stage: test
  needs: [build]
  parallel: 4
  script: [npm run test:integration -- --shard=$CI_NODE_INDEX/$CI_NODE_TOTAL]
```

## Fix 3: Runners Were the Real Bottleneck

None of the above matters if every job is still queued behind a single shared runner. Moving to autoscaling runners meant concurrent merge requests stopped competing for the same execution slot, which turned out to matter more for perceived pipeline speed during busy periods than any individual job optimization.

## Fix 4: Speed Without a Safety Net Is Just a Faster Way to Break Production

A twenty-minute pipeline that ships broken code faster is a worse outcome than a four-hour one that doesn't. Alongside the speed work, we added automated smoke tests against staging and a deployment validation gate before anything reached production, replacing what had been a purely manual "looks fine to me" step. That's what actually made shipping multiple times a day feel safe rather than reckless, and it's the piece that cut failed releases by roughly half even as release frequency went up.

## Result

Four hours down to twenty minutes, and multiple production releases in a single day went from theoretical to routine.

## Lessons

- **Measure before optimizing.** The fix was obvious once we had per-job timing; it wasn't obvious before.
- **Caching is usually the single biggest lever** in any CI pipeline, and it's almost always under-configured by default.
- **Parallelizing jobs doesn't help if they're all still queued on one runner.** Fix capacity and scheduling together, not one and hope the other doesn't matter.
- **Don't trade safety for speed.** Automate the validation gate so speed doesn't have to come at the cost of confidence.
