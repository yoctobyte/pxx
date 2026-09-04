---
slug: bug-t-test-core-reports-only-its-first-red-so-a-tier-with-three-failures-reads-as-one
title: "`make test-core` stops at the first failing recipe, so every later red hides behind the earliest one"
track: T
prio: 40
type: bug
status: backlog
found: 2026-09-05
found-by: frankB
owner-note: "filed by frankA from frankB's measurement; see the misattribution below, which is frankA's"
owner: ""
blocked-by: []
summary: "make stops at the first failing recipe, so test-core reports ONE failure however many it has. Measured 2026-09-05: frankB needed three passes to reach a broken leak row, because the AST slot-write census and one other recipe failed ahead of it and each run reported only the row it stopped on. `test-core is red` therefore reads as one problem when it is three, and the count is invisible until someone fixes them serially. tools/gate.sh quick has the opposite behaviour — it runs every check and prints a verdict per row — so the CHEAP tier reports completely and the expensive one reports one line."
---

# The measurement

frankB, 2026-09-05, fixing `bug-a-a-shortstring-in-array-of-const-boxes-an-unusable-pointer`'s
test row:

> *"`make test-core` stops at the FIRST failing recipe, and there are two
> earlier ones — the AST slot-write census at 11103 stopped my run before the
> leak row was ever reached, so I found this only on the third pass, after
> fixing what stood in front of it."*

Three distinct failures, three full runs to enumerate them, and after each run
the honest statement available was "test-core is red" — which is what gets
reported to a peer and read as a single problem.

# Why this is worth a ticket rather than a shrug

`tools/gate.sh quick` already does the other thing: sixteen checks, a `PASS` or
`FAIL` line each, then one verdict. Three separate gate runs on 2026-09-04/05
each named every row. So the repo already has the behaviour, in the tier that
runs in 90 seconds — and the tier that takes long enough that you only run it
when you must is the one that makes you run it three times.

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

# What to consider

`make -k` keeps going after errors and returns non-zero at the end, which is
most of the ask and is one flag. The reason not to do it blindly: some rows
genuinely depend on earlier ones having produced an artefact, and `-k` would
turn one real failure into a cascade of derived ones — noisier, not clearer.
So the question to answer first is **which test-core rows are independent**,
and the fix may be to run the independent ones under `-k` and keep the
dependent chain fail-fast.

**Do not "fix" this by making failing rows print more.** The defect is that
later rows never RUN, not that they are quiet.

# Gate

Whatever T's tooling change gate is, plus the specific check: break two rows
deliberately, run the tier once, and assert BOTH are named in the output.
That control is the whole ticket — a run that reports one row while two are
broken is the current behaviour and must fail.
