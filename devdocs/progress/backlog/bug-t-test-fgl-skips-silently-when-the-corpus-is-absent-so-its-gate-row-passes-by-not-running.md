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

## The pattern already exists one layer up — port it, don't design it (seven, 2026-08-30)

**Different surface, same problem, already solved.** This ticket is about the
**local `make test-fgl`** in a dev checkout. Track T's *tstate report md* has the
matching hazard and already handles it, with a banner worth copying verbatim:

> **COVERAGE: 1 job(s) DID NOT RUN on this box** (of 1 skipped). They are scored
> passlike, so they are invisible in the verdict above — a `RED` here speaks for
> the jobs that ran, not for the suite.
> - **host capability absent: rdrand — this CPU does not implement
>   RDRAND/RDSEED ... so the job cannot pass on this box and a red would be
>   permanent** — `test-core#939`

That is options 1 and 2 of this ticket, built, with the reason and the *identity*
of the missing job both printed. **So this stops being a design question and
becomes a port**, which is smaller and better specified: make the local target say
which subject was skipped and why, in that shape.

**And it strengthens the case rather than weakening it**, because the precedent is
in-house and was argued once already: `still_red` was added to the run record on
the reasoning that an archive naming nothing cannot answer *what* was red at a sha
without replaying every prior row. A skip that names nothing has the identical
property.

**Not affected by frankT's own correction.** It initially read a bare
`skip_holes: 1` in the ndjson as evidence the identity was unrecorded anywhere,
then found the report md names it and downgraded that finding to housekeeping (the
residue: 12 of 156 runs with a skip hole have no report file, so for those the
count is all that exists). None of that touches this ticket — the tstate side is
covered; the local `make` target is what still prints a pass for a test that did
not run.
