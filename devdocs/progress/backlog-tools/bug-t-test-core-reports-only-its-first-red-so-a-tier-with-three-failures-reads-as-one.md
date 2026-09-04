---
slug: bug-t-test-core-reports-only-its-first-red-so-a-tier-with-three-failures-reads-as-one
title: "`make test-core` stops at the first failing recipe, so every later red hides behind the earliest one"
track: T
prio: 40
type: bug
status: backlog
found: 2026-09-05
found-by: frankB
owner-note: "filed by frankA from frankB's measurement; amended by frankB, who owns the measurement. See the misattribution below, which is frankA's, and the summary correction below, which is frankB's."
owner: ""
blocked-by: []
summary: "make stops at the first failing recipe, so test-core reports ONE red however many it has, and reports whichever is EARLIEST IN THE FILE rather than newest, worst or yours. Measured 2026-09-05: two independent reds — an AST slot-write census entry and a leak row that could never pass — took three full runs to enumerate, and after the first fix the second presented as though the fix had caused it. tools/gate.sh quick has the opposite shape: it runs all sixteen rows, prints a verdict per row, and finishes in ~30s. The CHEAP tier reports completely and the expensive one reports one line, which is backwards for the tier that exists to give breadth."
---

# The measurement

frankB, 2026-09-05, landing `feature-pascal-typed-and-untyped-files` and fixing
`bug-a-a-shortstring-in-array-of-const-boxes-an-unusable-pointer`'s test row:

| run | stopped at | red |
| --- | --- | --- |
| 1 | `Makefile:10757` | `ast_slot_overloads.py` — two new spellings from that session's own change |
| 2 | `Makefile:11185` | `assert_no_leak.sh test_ssvarrec26` — a guard that could not pass (below) |
| 3 | — | exit 0 |

**Correction to this ticket's first draft, which said three reds: there were
two, and a third run to confirm green.** The argument is unchanged and the
correction is the point of the ticket in miniature — a count of reds that
nobody can enumerate in one run is a count people restate from memory.

Both reds were true before run 1 started. The sequencing is what misleads:
**after fixing red 1 the tier stopped at red 2, which looks exactly like "the
fix broke something else."** It had been sitting behind red 1 the whole time.
After each run the honest statement available was "test-core is red" — which is
what gets reported to a peer, and read as one problem.

# Why this is worth a ticket rather than a shrug

`tools/gate.sh quick` already does the other thing: sixteen checks, a `PASS` or
`FAIL` line each, then one verdict, in ~30s. So the repo already has the
behaviour, in the tier that is cheap — and the tier that takes long enough that
you only run it when you must is the one that makes you run it three times.

The cost compounds with the fleet: a red row that is not YOURS sits in front of
your row, and you cannot tell "my change broke something" from "someone else's
red is upstream of mine" without fixing theirs first.

**And the misattribution is not hypothetical — it happened in this ticket's own
filing.** frankA asserted that one of the reds ahead of frankB was frankA's own
stale AST slot-write snapshot, on the strength of having hit an AST-census red
the same evening on the same file. frankB checked instead of accepting it:
`git merge-base --is-ancestor 5bea302b5 HEAD` says frankA's fix was already in
frankB's tree before frankB started, and the actual diff was
`+AN_ASSIGN Left tmpIdent` / `+AN_ASSIGN Right destNode` — locals in a routine
frankB wrote that night. **Two agents hit "the AST census went red" hours apart
from two unrelated causes, and each had a ready story for why it was theirs.**
Acting on frankA's version would have had frankB drop its own snapshot
regeneration as redundant, putting the tier back to red and presenting as a
fresh regression to whoever hit it next.

That is the fleet-scale version of the defect: **a tier that names one row makes
"the census is red" a shared symptom with no owner attached**, and a plausible
owner is then supplied by whoever spoke last.

# The second red is why this one became visible at all

`assert_no_leak.sh test_ssvarrec26 200` over
`test_shortstring_in_array_of_const.pas` had **never been able to pass**: a
straight-line test with eight `Format` calls and no loop, 33 allocations against
the script's floor of 100. `assert_no_leak.sh` refuses below the floor rather
than reporting a false PASS, which is the script being right — a per-iteration
leak cannot be told from a handful of live handles at exit.

Fixed in `1c274a83b` by changing the **subject** (500 silent boxing iterations;
`live=24` against the bound of 200, and the same census against a bound of 5
reports `LEAK`, so the row now has a positive control). **Not** by lowering the
floor. frankA's phrasing of the distinction, kept because it is better than the
original: *raising the iteration count changes the SUBJECT so the instrument can
resolve it; lowering the floor would change the INSTRUMENT so it reports on
noise. From outside both look like "make the row pass" and only one leaves a
guard behind.*

**That row was red on origin/master for every session running `test-core` from
the commit that added it. Nobody saw it, because everybody who ran the tier
stopped earlier.** That is the concrete cost of this ticket, and it is not
hypothetical either.

# What to consider — three repairs, and the choice is real

This is not a `make` defect; it is `make` semantics — one target, one shell per
recipe line, stop on nonzero. So it is fixable in at least three ways:

1. **`make -k test-core`.** One flag, keeps going, exit status still says
   something failed. Cheapest, and it gets the enumeration without touching a
   line of the Makefile. Cost: recipe lines that depend on an earlier line's
   artefact produce cascade noise — one real failure becoming several derived
   ones is noisier, not clearer.
2. **A per-row runner**, the way `gate.sh` already works, with the row list
   generated from the target. Best output, most work, and it duplicates the
   Makefile's own knowledge of what the rows are.
3. **Split the target** into sub-targets invoked by a driver that runs all of
   them and summarises. Middle cost; the split lines are arbitrary and go stale.

**Recommend 1 first, and MEASURE the cascade noise before considering the
others.** If `-k` on a deliberately-reddened tier yields the real reds plus two
cascades, that is already the whole win for one flag. The question that decides
between 1 and 3 is **which test-core rows are independent** — the answer may be
"nearly all of them", in which case 2 and 3 are never needed.

**Do not "fix" this by making failing rows print more.** The defect is that
later rows never RUN, not that they are quiet.

# Gate

Whatever T's tooling change gate is, plus the specific check: **break two rows
deliberately, run the tier once, and assert BOTH are named in the output.**
That control is the whole ticket — a run that reports one row while two are
broken is the current behaviour and must fail.
