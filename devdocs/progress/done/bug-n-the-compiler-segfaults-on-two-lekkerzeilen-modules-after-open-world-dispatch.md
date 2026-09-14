---
slug: bug-n-the-compiler-segfaults-on-two-lekkerzeilen-modules-after-open-world-dispatch
track: N
type: bug
prio: 90
status: resolved
owner: ""
created: 2026-09-10
resolved: 2026-09-14
found-by: frankuser
tags: [nilpy, lekkerzeilen, crash, dispatch, regression]
blocked-by: []
summary: "GONE at HEAD 6d059b47f, measured 2026-09-14: `traffic.py` rc=0 and `vessel.py` rc=0, three runs each, no core. Both modules now COMPILE -- traffic.py emitting 60 `dispatching on the receiver at run time` warnings and vessel.py 42. Closed by events over the four nights of Track N receiver-dispatch work, not by anyone holding this ticket. THE FIXING COMMIT IS NOT ESTABLISHED and this resolution does not claim one: the strongest candidate on shape alone is 189259975 `fix(N): a class-reference receiver no longer walks RTTI off a non-instance`, and verifying that costs a build at 189259975^ plus one at 189259975, which nobody has spent. The 42-warnings-in-both coincidence the original summary flagged as a fan-in tell is now resolved the other way: the counts DIVERGE (60 vs 42), so they were never one shared site. Reopen on a fresh rc=139, not on this reasoning."
---

# Measured 2026-09-10

```
compiler 546d4dcbd305, tree 08d8d5170
  traffic.py   Segmentation fault (core dumped)   rc=139
  vessel.py    Segmentation fault (core dumped)   rc=139
  pinned v407  traffic.py                          rc=1   (ordinary error)
```

42 `dispatching on the receiver at run time` warnings in each before the crash,
on `.water_height()`, `.current()`, `.depth()`, `.bed_height()`, `.wind()`, plus
one `several unrelated classes declare a .up property — reading it through the
receiver at run time`.

# Why it only became visible now

These two modules were blocked at `math.atan2` until `0838c1be3`. Clearing that
wall let them compile far enough to reach this, which is the first-wall mechanism
delivering a CRASH instead of the expected next refusal. **Four null rows taught
us to expect a new wall; none of them predicted the new wall would be a
segfault.**

The open-world dispatch work is the obvious suspect given the 42 warnings
immediately preceding, and **that is a suspicion, not a bisect.** Not attributed
to a commit: the range between v407 and `08d8d5170` contains several seats' work,
and CLAUDE.md is explicit that a tier or census delta gets attributed to a RANGE
before it gets attributed to anyone. frankZ holds dispatch and should look first,
but the honest next step is `git bisect` over that range, not a reading.

# THE INSTRUMENT FAILED TOO, AND THAT IS WORTH ITS OWN LINE

The census that found this reported both rows as `FAIL <module> ::` with an
**empty reason**, because the harness did `grep -m1 'error'` on the log and a
segfault writes no `error:` line — the log holds 42 warnings and then stops. So a
crash rendered as the least alarming row in the output, less informative than
every ordinary refusal beside it.

**A harness that extracts a reason by matching a word cannot report a failure
that produces no words.** The fix is to branch on the exit code first and only
then look for text — `rc=139` is unmistakable and needs no parsing. Any census
over this corpus should do the same, and the two empty rows were nearly read as
an uninteresting formatting glitch.

# Scope honesty

Not minimised. Both reproducers are real 600-line application modules, so the
first job is to shrink one — the 42 warning sites are the obvious place to start
cutting, and the shared-import hypothesis predicts that a single site in a
COMMON dependency will reproduce it alone.

# RE-MEASURED 2026-09-14 — it does not reproduce

Tree `6d059b47f`, compiler built at that tree, three runs per module, from the
owner's checkout (`/home/neo/lekkerzeilen`, read-only):

```
traffic.py   rc=0  rc=0  rc=0    60 `dispatching on the receiver at run time`
vessel.py    rc=0  rc=0  rc=0    42 `dispatching on the receiver at run time`
```

No segfault, no core, and both modules now reach a binary.

## The 42/42 coincidence was not a fan-in tell, and it is worth saying which way

The original summary read the identical 42 warnings across two unrelated modules
as evidence of ONE crash site reached through a shared import — the same
reasoning that correctly collapsed five `*`-unpacking rows into three. At HEAD
the counts are **60 and 42**. They diverge, so the modules were never sharing a
site and the inference was wrong. It was a reasonable read and the discriminator
was always cheap; nobody ran it while the ticket was open because the crash made
the warning counts look like scenery.

## What is NOT established

**Which commit fixed it.** Four nights of Track N receiver-dispatch work sit
between the report and now. On shape alone the candidate is
`189259975 fix(N): a class-reference receiver no longer walks RTTI off a
non-instance` — a receiver-dispatch crash walking RTTI off something that is not
an instance is exactly what 42 dispatch warnings followed by a silent SIGSEGV
looks like. **That is a hypothesis, not a measurement.** What would settle it:
build at `189259975^` and at `189259975` and run `traffic.py` against each. Two
self-host builds, and nobody has spent them.

The residual question therefore has an owner named here rather than being left
implied: anyone who sees an rc=139 from this shape again should start at that
pair of builds rather than re-deriving the ticket.
