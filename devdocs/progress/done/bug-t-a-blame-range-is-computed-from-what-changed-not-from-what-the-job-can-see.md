---
slug: bug-t-a-blame-range-is-computed-from-what-changed-not-from-what-the-job-can-see
title: A blame range is computed from what changed, not from what the job can see
track: T
prio: 60
status: done
owner: pxx-aa
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

## Face 4: a job's FIRST run inherits a range it never earned (fixed 2026-08-26)

`diff_jobs()` read a job's previous status as `prev_jobs.get(n, "pass")`. One
default answering two questions that are still distinct at that exact point in
the code — *was it green* and *did it ever run* — and collapsing them where the
information to tell them apart still exists.

For the **verdict** the default is right: a job that is red the first time it
runs must be reported red, not absorbed. For the **range** it is fiction: there
is no earlier passing sha, so no interval contains the cause, and every commit
a range could name is equally innocent.

Worst of the four, because a bisect over such a range does not fail. It
terminates, prints a sha, and is indistinguishable downstream from a correct
answer.

**Surfaced by enrolling test-fgl and test-fpjson**, and structurally so:
enrolling a rung is the only thing that creates a never-seen job, so only
whoever enrols can trip it — and nothing had been enrolled in long enough for
it to matter.

Fix: `diff_jobs()` returns `first_seen`; a first-seen red opens with an **empty
range**, which routes it to the sentence `range_note()` already contained and
nothing could reach — *"range unknown (first run covering this job at this
tier, so there is no earlier passing sha to bound it) — no idle bisect will
happen; this one needs hand-triage."* The regression carries `first_seen: True`
so a reader can tell the two cases apart. `tools/twatch_first_seen_devtest.py`
guards both halves, including the one that must NOT change (red on arrival is
still a NEW-RED) and the mirror case (a first-ever PASS is not a FIXED).

Face 3 (the pin axis) remains open; this ticket stays in the backlog for it.

## Face 3 fixed 2026-08-26 — the ticket is now closed

The axis is expressed in the **existing type** rather than a new one: a
pin-built regression's `range` becomes the list of commits in range that
**moved the pin**. Those are exactly the events the job can observe, they are
still commits so `bisect_step` needs no teaching, and pin.log commits touch
`stable_*/**` so `testable_only()` keeps them. `pins_in_range()` already
computed precisely this set for a different purpose.

### The first cut of this was WRONG in the dangerous direction — corrected same session

The first attempt replaced the range with **pin moves only**: 137 commits down
to 2. That is too narrow, and too narrow is the failure that matters
(`last_covering_sha`'s own docstring: *"a too-wide range costs bisect steps; a
too-narrow one can exclude the culprit"*). `make pin` freezes
`compiler/builtin/**` and **deliberately leaves `lib/rtl` and `lib/pcl` live** —
"track B's own editable lane, which B expects live" — and the job compiles
`test/lib_mimic_xml_etree_elementtree.npy` from the live tree. So a pin-built
job is blind to `compiler/**`, **not** to everything but the pin. Measured: the
137 contain 2 `lib/` and 34 `test/` commits, all of them genuinely causal
candidates, and the pin-move cut discarded every one.

The right predicate already existed and was already correct: `PIN_IMMUNE_PREFIXES`
(`compiler/`, `tools/`, `devdocs/`, `docs/`). `pin_immune()` applies it to the
ONE accused commit; nothing applied it to the range. Which is this ticket's own
thesis, one more time — the decision was right, the publication was wrong, and
the predicate was sitting there.

Measured against the live regression that motivated the ticket:

```
lib-test#src:test/lib_mimic_xml_etree_elementtree.npy
  137 commits  ->  37 observable   (dropped 100 that change only compiler/tools/docs)
```

A bisect over 37 candidates instead of 137, with nothing causal discarded — and
the 100 dropped include the anchor `fd93e4a71c37`, a tstate publish commit,
which changes nothing at all. An unknown file list never narrows: a commit whose
paths cannot be read is kept.

**Repaired on read**, like the untestable-commit filter: a regression opened
before this change carries a commit range for a job that cannot observe
commits, and waiting for it to age out means the board prints the wrong axis
for as long as it stays open. That is already days for the one above.

`range_note()` now speaks the axis, including the verdict that was previously
inexpressible: *"no pin moved between `good` and `bad`. This job builds only
with `$(PXX_STABLE)`, so its compiler did not change across the interval — the
cause is in the test's own inputs or the box, **not** in the commits."* Every
red on a pin-built job used to implicitly assert "something in the compiler
changed"; across an interval with no pin transition that is simply false.

### All four faces, closed

| face | fix |
| --- | --- |
| wrong anchor | `c68e6492e` |
| untestable commits in range | `cf7d805d4` |
| **wrong axis (pin-built)** | **this change** |
| first-ever run inherits a range | `663214041` |

Guarded by `tools/twatch_first_seen_devtest.py` (9 cases), which covers both
axis wordings, the empty-pin-axis verdict, and the ordinary commit range that
must stay unchanged.

## Log
- 2026-08-26 — resolved, commit 4672796d0.

## Two follow-ups the correction exposed

**1. The repair was one-way, and would have latched the wrong rule in.**
`pin_axis` was a boolean, so "already repaired" was indistinguishable from
"repaired under a rule we have since corrected" — and the first rule *was*
wrong. A regression narrowed by it could never have been re-widened. It is now
a rule VERSION (`PIN_AXIS_RULE`), and the repair **re-derives from `good`/`bad`**
rather than filtering the stored range in place. Filtering in place cannot give
back what a wrong rule dropped, and storing the unfiltered range to make it
reversible would put a novel in a git-committed state file. Bump the constant
and every open regression re-derives on the next idle pass.

**2. The repair called a name that was not in scope.** `testable_only` reads as
a module helper and is a closure nested inside `test_sha`. It parsed, it read
correctly, and it passed a devtest that grepped the source for the call — a
text check cannot see a scoping bug. It would have raised `NameError` the first
time the daemon reached that branch: on an idle cycle, hours later, in a
process nobody was watching.

There is no pyflakes/flake8/ruff on these boxes, so
`tools/tools_scope_devtest.py` is the narrowest useful substitute. It reports
exactly one class — *a name LOADED where it is not in scope but BOUND somewhere
else in the same file* — which is the pairing that makes it near
false-positive-free, and which is exactly the mistake a large file full of
nested helpers invites. Verified against the real defect, not a synthetic one:
re-injecting the call makes it print
`bisect_step() calls 'testable_only', which is bound in another function's scope`.

Deliberately not a general linter: a checker that reports everything gets
suppressed, and a suppressed checker asserts nothing.
