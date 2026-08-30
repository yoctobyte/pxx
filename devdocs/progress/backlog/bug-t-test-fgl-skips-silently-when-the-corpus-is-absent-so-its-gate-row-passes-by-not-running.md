---
slug: bug-t-test-fgl-skips-silently-when-the-corpus-is-absent-so-its-gate-row-passes-by-not-running
title: "test-fgl skips silently when the corpus is absent, so a gate row naming it passes by not running"
track: T
prio: 55
type: bug
status: new
blocked-by: []
owner: ""
summary: "This checkout has neither fgl.pp nor the fpc-testsuite, and test-fgl SKIPS rather than failing or announcing. A gate line saying `test/fgl/objectlist.pas must compile` is therefore satisfiable on this box by not running the test at all. Found by frankS while fixing the p70 constraint regression -- it had to run against read-only copies from other clones to get a real answer."
---

# `test-fgl` skips silently when the corpus is absent

Found by frankS, 2026-08-30, while fixing
[[regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section]].

This checkout has neither `fgl.pp` nor the fpc-testsuite. `test-fgl` **skips**
— it does not fail, and it does not announce loudly enough that a reader
distinguishes "passed" from "was not run". frankS had to run against read-only
copies from `/home/neo/frankA/` and `/home/neo/frank1/` to get a real answer.
(Nothing written in either.)

## Why this is worse than a missing test

I set that ticket's gate as *"`test/fgl/objectlist.pas` compiles and runs"*. **On
this box that row is satisfiable by not running it.** A gate whose green is
indistinguishable from its absence is the same failure family as a guard that
cannot fire and a control that was never measured — and it is the one the
coordinator most relies on, because a gate line is what a dispatch cites when it
says the work is provably done.

It is also selectively invisible: the agent who *has* the corpus (Track T's
watcher clone, another dev clone) sees a real verdict, so the hole appears only
for whoever happens to lack it. That is the reverse of a normally-flaky test,
which announces itself.

## What to do — options, not a decision

1. **Make the skip loud** — a distinct exit status or a `SKIPPED (corpus absent)`
   line that testmgr records as `skip`, not as absence. Cheapest, and it is what
   makes the other options unnecessary in the common case.
2. **Vendor the two fgl drivers' inputs** so the job cannot skip. Contradicts the
   no-vendor gate row.
3. **Fail when the corpus is absent** but the job was explicitly requested by
   name. Right for a gate, wrong for a routine sweep.

Recommend (1) plus (3)-when-named. The general property to preserve:
**a job's absence and a job's pass must never print the same thing.**

## Related

The corpus-availability question is the same one that blocks
[[feature-pascal-corpus-oop]] (needs `fpc-source-3.2.2`, not installed).
