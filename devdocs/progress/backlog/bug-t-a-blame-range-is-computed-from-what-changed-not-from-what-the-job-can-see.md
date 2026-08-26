---
slug: bug-t-a-blame-range-is-computed-from-what-changed-not-from-what-the-job-can-see
title: A blame range is computed from what changed, not from what the job can see
track: T
prio: 60
status: backlog
---

## The shape, stated once

Three times this week a blame range pointed confidently at commits that could
not have caused the failure. Three different mechanisms; one root cause.

| face | the range said | why it could not be true | status |
| --- | --- | --- | --- |
| **wrong anchor** | `bad` = a sha that ran no such job | the anchor came from the run, not from the last run that COVERED this job at a bounding tier | fixed, `c68e6492e` |
| **untestable commits in range** | 250-line `prio:` frontmatter commit named as culprit for four unrelated jobs | a commit touching no code a gate observes cannot change a verdict; bisecting over it names an innocent | fixed, `cf7d805d4` |
| **wrong axis entirely** | `lib-test#…xml_etree_elementtree`: 137 commits of range | the job is `pin_built` — it builds with `$(PXX_STABLE)`, so it is blind to all 137. Its verdict moves when the PIN moves | **open — this ticket** |

The common defect: **the range is derived from what changed in the repo,
without asking whether this job could observe it.** Each fix so far has
answered that question for one face. `needs_test()` asks it for face 2. Nothing
asks it for face 1's tier coverage in the general case, and nothing asks it at
all for face 3.

## Face 3 in detail — the pin axis

`pin_immune()` already gets the *decision* right: it refuses to bisect a
pin-built job whose accused commit moved no pinned binary, and says so out
loud. That half works and is not the bug.

The bug is that the range is still **computed and published** on the commit
axis, so `TSTATE.md` prints "bad `fd93e4a71c37`, last good `98ed38202254`, 137
commit(s) in range" for a job to which those 137 commits are invisible. A human
reading the board sees a lead. There is none. Worse, `fd93e4a71c37` is a
*tstate publish commit* — the watcher's own — so the accusation is not merely
imprecise, it names a commit that changes nothing at all.

For a pin-built job the interval that carries information is **pin-to-pin**:
the job's compiler is the pinned binary, and the only events that can change
its verdict are the ~3.4/day pin moves recorded in
`stable_linux_amd64/default/pin.log`. `pins_in_range()` already reads that log
for a related purpose, so the data is in hand.

## Proposed fix

Do not special-case; give the range an **axis** chosen from what the job builds
with (`devdocs/dev/normalise-dont-special-case.md` — the second path is the one
that stays broken).

1. When a regression's job is `pin_built`, compute `range` over **pin
   transitions** from `pin.log` between `good` and `bad`, not over commits.
   Render it as `v374 → v375` rather than a commit count.
2. When that range is empty (no pin moved between good and bad), say so
   explicitly: *"no pin moved in this interval — this job's compiler did not
   change, so the cause is in the test's own inputs or the box"*. That is a
   real, useful verdict and today it is unreachable.
3. `range_note()` gains the pin-axis wording, the way it already refuses to
   promise a bisect it cannot deliver.
4. A guard in the devtest family, in the shape of
   `testmgr_pin_built_devtest.py`: a pin-built regression must never publish a
   commit-axis range.

## Why prio 60 and not higher

It publishes a misleading lead, it does not corrupt a verdict — `pin_immune()`
stops the bisect, so no cycles are burned chasing it and no innocent commit is
recorded as culprit in the ledger. The cost is a human minute per read, and the
risk is that someone acts on the lead before reading the pin-provenance note.

## Credit

The generalisation is frank1-72's, from the v375 pin exchange: *"the range is
computed from what changed, without asking whether the job could see it… the
three look like one thing from here."* Filed as one ticket rather than three
because the third fix should delete the shared defect, not add a third case
(`devdocs/dev/root-cause-over-microfix.md`).
