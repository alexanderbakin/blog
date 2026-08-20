---
title: "The Wildcard That Broke Nginx Log Rotation"
slug: "logrotate-wildcard-bug"
date: 2025-07-05T00:00:00Z
draft: false
tags:
  - Nginx
  - Logrotate
  - Linux
  - DevOps
  - SysAdmin
categories:
  - Linux
---

One of those infrastructure problems that looks simple, until you realize the filename itself is part of the problem.

## The Setup

We had Nginx configured to handle wildcard subdomains: `server_name *.example.com;`, with access logs named after the server block. That's a convenient pattern for multi-tenant setups where subdomains get created dynamically and you don't want to hand-maintain a vhost file per tenant. Nginx doesn't care that the resulting log filename contains a literal `*` - it just opens the file and writes to it.

The log ended up on disk as:

```
/var/log/nginx/*.example.com.access.log
```

Everything worked perfectly from Nginx's side: requests were logged, the file was created, and it grew as expected.

## The Symptom

The problem showed up in logrotate, not Nginx. Logs were configured to be retained for two weeks (`rotate 14`), but some rotated copies were disappearing after only a couple of days. Not consistently, either - it depended on what other files happened to be sitting in the same log directory at rotation time.

That inconsistency was the first clue. A deterministic bug would have been faster to chase.

## Root Cause

Logrotate matches files using glob patterns. Globbing treats `*` as "match anything," not as a literal character. That's fine when `*` shows up in a *pattern* you wrote on purpose. It stops being fine the moment `*` shows up in an actual *filename*, because any tool that later re-globs based on that name will treat it as a wildcard too.

You can see the same failure mode from a plain shell:

```bash
$ ls
*.example.com.access.log   a.example.com.access.log   b.example.com.access.log

$ ls *.example.com.access.log*
*.example.com.access.log  a.example.com.access.log  b.example.com.access.log
```

Asking for "the rotated copies of *this one file*" instead matched every file in the directory ending the same way, because the leading `*` in the real filename got expanded as a wildcard by the shell. Logrotate does the equivalent of this internally when it looks for a log's previously rotated copies - so rotating the wildcard-named log could scoop up (and count against retention, or prune) files belonging to completely unrelated vhosts sitting in the same directory.

## The Fix (For Now)

The immediate, practical fix was to stop putting `*` in the filename at all:

```
*.example.com  →  _.example.com
```

Renamed the log path in the Nginx config, reloaded, done. Retention went back to being deterministic immediately.

This is a workaround, not a fix - the actual bug lives inside logrotate itself, in how it rebuilds glob patterns from filenames it should be treating as literal strings. That's a deeper problem than a naming convention, and it deserves a proper look rather than a quick rename. For now, the workaround holds and retention is predictable again.

## Lessons

- **Know how your tools interpret special characters.** Shell globbing, regular expressions, and configuration parsers don't necessarily agree on what a given character means.
- **Test logrotate configurations before deploying them.** A config can look perfectly reasonable while matching something completely different than intended.
- **Debug the actual filenames.** `ls`, `find`, and logrotate's own debug output (`logrotate -d`) will quickly show whether a pattern matches what you think it matches.
- **Be careful with wildcard-based infrastructure.** Wildcard domains are convenient, but they can introduce unexpected edge cases the moment their names become filenames, paths, or identifiers somewhere else in the stack.

It's a small problem, but exactly the kind that makes infrastructure work interesting: everything is technically working, and one character causes a couple of hours of debugging.
