---
slug: bug-n-the-compiler-segfaults-on-two-lekkerzeilen-modules-after-open-world-dispatch
track: N
type: bug
prio: 90
status: backlog
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, lekkerzeilen, crash, dispatch, regression]
blocked-by: []
summary: "`./compiler/pascal26 lekkerzeilen/traffic.py` and `lekkerzeilen/vessel.py` SEGFAULT at tree 08d8d5170, compiler 546d4dcbd305 -- rc=139, core dumped, reproduced three times each. It is NEW: pinned v407 exits rc=1 on the same file (an ordinary error, because it stopped at math.atan2 long before this point). Both modules emit exactly 42 `dispatching on the receiver at run time` warnings before dying, and the identical count across two unrelated modules suggests ONE crash site reached through a shared import rather than two -- the same fan-in artefact that made five *unpacking rows look like five sites when they were three. A crash outranks every other wall on this target: it is the only failure mode on the board that produces no diagnostic at all."
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
