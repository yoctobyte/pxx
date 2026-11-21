---
prio: 70
track: T
type: bug
status: done
found: 2026-09-22
found-by: frankh-c0
owner: "claude-pxx"
blocked-by: []
summary: "FIXED 2026-11-21: `--status` names a tstate(...) bound as the watcher's own bookkeeping commit and points at the range (bad_qualifier, is_tstate_commit). Originally: TRACK T DETECTED THE x86-64 C BUILD REGRESSION AT THE FIRST FULL TIER THAT CONTAINED IT, AND ITS OWN REPORT TOLD THE READER THERE WAS NOTHING TO FOLLOW. Verified: `test-emit-obj#src:test/c_obj_data_import.c` transitions to `new_red` at f64af0fd3a0c, the full tier whose tree contains 523833fde (the bisected cause, frankb-8e), after being `fixed` since 2026-09-12. So breadth worked -- the detection is not the defect. What `twatch.py --status` then prints is `open CASCADE: 17 of 17 swept job(s) still red, bad=f64af0fd3a0c (3 in range) -- bad touches NO buildable file: it is the tested upper bound, not a lead`. AND f64af0fd3a0c IS A COMMIT TRACK T ITSELF AUTHORED: its subject is `tstate(borg): c6208f6d47c6 RED (native)`, one of the archive-bookkeeping commits the watcher writes. So T's bisect range is bounded by T's own writes, the bound correctly touches no buildable file, and the honest observation `not a lead` is the last thing a reader sees about a 17-job cascade that had a real and findable cause nine commits earlier. This is CLAUDE.md's `any instrument that scans a namespace THE OBSERVER IS ALSO IN counts the observer` -- written there about pgrep/pkill -- arriving in the COMMIT RANGE a bisect walks. NOT VERIFIED and the reason the prio is 70 rather than higher: I did not establish how often a cascade bound lands on a tstate commit rather than a real one, nor whether the bisect deliberately excludes them and this was an exception. One number would decide whether this is a papercut or the normal case, and a T seat can get it from the archive in one query. The remedy is probably not to suppress the message: `bad touches no buildable file` is TRUE and worth printing. It is that a bound which is one of T's OWN commits should say so by name and widen, rather than reporting the same sentence it would print for an ordinary docs commit."
---

# A cascade bounded at Track T's own bookkeeping commit reports itself as "not a lead"

## What is verified

`tools/twatch.py --job-history "test-emit-obj#src:test/c_obj_data_import.c"`:

    2026-09-12T08:43:01Z borg  48ffab327c36  full  fixed
    2026-09-22T17:02:23Z borg  f64af0fd3a0c  full  new_red
    last transition was new_red — still open as of 2026-09-22T17:02:23Z.

`git merge-base --is-ancestor 523833fde f64af0fd3a0c` → yes, 9 commits between.
`523833fde` is the bisected cause of
`bug-c-a-c-file-compiles-to-an-object-only-if-it-happens-to-contain-a-pascal-keyword`
(bisected by frankb-8e: its parent builds, it does not).

**So Track T caught it at the first full tier that contained it.** Breadth did
its job. The detection is not what is wrong here.

What `twatch.py --status` prints:

    open CASCADE: 17 of 17 swept job(s) still red, bad=f64af0fd3a0c (3 in range)
      — bad touches NO buildable file: it is the tested upper bound, not a lead

And:

    $ git log -1 --format='%s' f64af0fd3a0c
    tstate(borg): c6208f6d47c6 RED (native)

**`f64af0fd3a0c` is a commit Track T wrote.** It is one of the archive
bookkeeping commits the watcher lands after a run.

## Why that is the observer-in-the-namespace rule again

CLAUDE.md states it about process tables: *"any instrument that scans a namespace
THE OBSERVER IS ALSO IN counts the observer"*, with `ps`/`pgrep`/`pkill` as the
named examples. A bisect walks a **commit range**, and Track T commits into that
same range every time it records a verdict. So T's own writes are eligible to be
a bisect bound, and when one is, every downstream sentence is correct and points
nowhere:

- `bad touches NO buildable file` — true, it is a `tstate/**` write.
- `it is the tested upper bound` — true.
- `not a lead` — true *about that commit*, and the last thing the reader sees
  about a 17-job cascade with a real cause nine commits back.

None of it errors. All of it answers. It is the house failure mode with a
bisect as the instrument.

## What makes this worth a ticket rather than a shrug

The alternative diagnosis for this regression was "the emit-obj tier is not in
`gate.sh quick`, so a seat can be green while having broken every x86-64 C
build." That is true and is a real gap. But it frames the problem as *missing
coverage*, and the coverage was not missing: T had it, T ran it, T went red on
it within one tier. **The gap is between detection and a reader acting on it**,
and that is a much cheaper thing to fix than adding rows to a fast gate — which
CLAUDE.md warns costs the machine that produces breadth in the first place.

## NOT established, and it decides the priority

- **How often a cascade bound lands on a `tstate(...)` commit** rather than a
  real one. If it is rare, this is a papercut. If it is common — and T commits
  after every run, so the base rate is not obviously low — then "not a lead" is
  a sentence the fleet reads regularly about cascades that do have leads.
  A T seat can get this from the archive in one query; I did not.
- **Whether the bisect deliberately excludes T's own commits already** and this
  was an exception. I did not read the bisect's selection code.

I am filing rather than fixing because both of those are answerable only from
inside the archive, which is T's lane and T's tooling, and because the useful
form of this ticket is one number rather than a patch from someone who has not
read the selector.

## Suggested shape, offered not prescribed

Do **not** suppress `bad touches no buildable file`. It is true and it is
exactly the right thing to print for an ordinary docs commit. The problem is
that a bound which is one of **T's own** commits gets the same sentence as a
stranger's docs commit. Naming it — *"the bound is a tstate bookkeeping commit
this watcher wrote; widening"* — turns a dead end into an instruction, and costs
one branch.

## Provenance

Found while answering a question frankb-8e raised about which guard should have
caught the C regression. It should not be read as a criticism of breadth: the
measured fact is that breadth worked and the report did not carry it.

## Fixed 2026-11-21 (claude-pxx)

The suggested shape, taken as offered. `bad_qualifier` (the `--status`
suffix, which CASCADE lines carry too) still prints
`bad touches NO buildable file: it is the tested upper bound, not a lead`
for an ordinary docs commit. When the bound is one of the watcher's OWN
commits -- subject `tstate(<host>): ...`, which every publish writes -- it now
says instead:

    — bad is a tstate bookkeeping commit this watcher wrote, not a lead:
      the cause is EARLIER in the range; read the range, not bad

Not suppressed and not widened: the range itself is already the right
instruction, and the stub ticket's range note says "the upper bound of an
untested range" already. What was missing was the one line a reader acts on
naming whose commit the bound is. `is_tstate_commit` reads the subject and
answers False for a sha it cannot read.

**Not established, and still the open question in this ticket:** how often a
cascade bound lands on a tstate commit. The fix costs one `git log` per
non-buildable bound either way, so it does not wait on that number.

Test: tools/twatch_cascade_qualifier_devtest.py. Its docs-only commit was a
tstate publish, so the old checks are now made against an ordinary devdocs
commit, and four new ones cover the tstate case (named; points at the range;
still "not a lead"; an ordinary docs commit does not get the wording).
