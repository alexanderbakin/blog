---
title: "Fixing logrotate's Glob Confusion"
slug: "logrotate-fix"
date: 2026-08-20T00:00:00Z
draft: false
tags:
  - Logrotate
  - Linux
  - Open Source
  - C
  - DevOps
categories:
  - Linux
---

A follow-up to [the wildcard bug post](/logrotate-wildcard-bug/) from last year.

## Picking the Thread Back Up

The rename workaround, `*.example.com` to `_.example.com`, fully resolved the operational problem. Retention became predictable again, and there was no pressing reason to go further. But a workaround isn't a fix, and the actual bug was still sitting in logrotate's own source, waiting to bite the next person who names a file after a wildcard domain. This week I finally sat down and found it properly, instead of just renaming files around it.

## Where the Bug Actually Lives

When logrotate rotates a log, it needs to find that log's own previously rotated copies, either to renumber them (classic numbered rotation) or to prune the oldest ones past the retention count (`dateext` mode). It finds them by building a glob(3) pattern from the log's basename and calling `glob()`:

```c
asprintf(&pattern, "%s/%s<suffix>", rotNames->dirName, rotNames->baseName);
glob(pattern, 0, globerr, &globResult);
```

The bug is right there: `baseName` is the *already-resolved, literal* name of the real file being rotated. It isn't a pattern anyone wrote - it's just a filename. But it gets handed to `glob()` as if it were one. If that filename itself contains a glob metacharacter, most notably `*`, it gets re-interpreted as a wildcard a second time.

There are three places in the codebase that make this mistake:

- `findLastRotated()` - classic numbered rotation
- the delayed-compress lookup inside `prerotateSingleLog()` - `dateext` mode
- the excess-rotation pruning lookup inside `prerotateSingleLog()` - also `dateext` mode

Concretely: rotating `*.example.com.access.log` builds a lookup pattern that, because of the leading `*`, matches *any* file in the directory ending the same way - including the rotated copies of completely unrelated vhosts sitting next to it. Those get folded into the same match set, the count of "how many old copies exist" comes out wrong, and once it looks like there are more than `rotate` copies, logrotate deletes the oldest ones. Those oldest ones might belong to a different log entirely.

That's a meaningfully worse failure mode than what I saw last year. It isn't just "this log's retention window is shorter than configured" - it's logrotate quietly deleting another log's rotated files because two unrelated filenames happened to collide under the same re-interpreted glob.

## The Fix

![Terminal screenshot: reproducing the bug with logrotate --force removing a.example.com and b.example.com's rotated logs as "wrong file" when rotating the literal *.example.com log, and the one-line fix wrapping the glob pattern in globEscape()](/images/logrotate-fix-terminal.png)

The fix escapes glob metacharacters when building these internal bookkeeping patterns, so a log's own basename is matched literally instead of glob-interpreted. I added a regression test that reproduces the exact scenario: three logs, `a.example.com`, `b.example.com`, and the literal `*.example.com`, all under `dateext` with `rotate 3`. Before the fix, rotating the `*.example.com` entry deletes rotated copies that `a.` and `b.`'s logs had just correctly kept. After the fix, it doesn't touch them.

Opened it as [logrotate/logrotate#722](https://github.com/logrotate/logrotate/pull/722) (+147/-7).

## Why This Took a Year

Honestly, because the workaround was good enough. Renaming the wildcard vhost logs cost nothing and fully removed the operational pain, so there was no urgency to go spelunking through logrotate's C source for a proper fix. Coming back to it now was less about need and more about closing the loop - contributing the actual fix upstream so the next person running Nginx wildcard vhosts doesn't have to rediscover this the hard way.

## Takeaway

The pattern underneath both posts is the same: `glob()` called twice on the same string. Once implicitly, when the filename gets created (Nginx just writes to whatever path its config says). Once explicitly, when some other tool later treats that name as a pattern to search with. Whenever a name that was itself the *output* of one system becomes the *input* to another as a pattern rather than a literal, characters that were completely harmless as identifiers can quietly turn into operators. It took a year to circle back to it, but closing it out felt good.
