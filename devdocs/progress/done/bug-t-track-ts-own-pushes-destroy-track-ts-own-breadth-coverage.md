---
slug: bug-t-track-ts-own-pushes-destroy-track-ts-own-breadth-coverage
track: T
type: bug
prio: 45
status: done
blocked-by: []
summary: "NOTEST_PREFIXES is ('devdocs/', 'docs/'), so tools/** is testable — correct, since a testmgr change can change results. The consequence is that Track T is the only lane whose ordinary work systematically destroys its own coverage: any T tooling push aborts an in-flight idle-phase full tier and discards 100% of it. Measured 2026-08-19: one twatch push killed the first breadth run in 5h13m at ~207/2765 jobs. Batching by hand is a habit, not a property."
---

# Track T's own pushes destroy Track T's own breadth coverage

## The finding

`make_preempted()` aborts idle work when any commit since the tested sha
`needs_test()`, and:

```python
NOTEST_PREFIXES = ("devdocs/", "docs/")
```

So `tools/**` is testable. **That is correct and should not change** — a
`testmgr.py` change can change what every job reports, and a watcher that
ignored its own tooling would be publishing verdicts about code it did not test.

The consequence is structural: **T is the only lane whose ordinary work
systematically destroys T's own coverage.** Every other lane pushes
`compiler/**` or `lib/**` and preempts a run that was testing a *previous* sha;
T pushes the tool doing the testing, and the discard is total.

Measured 2026-08-19, self-inflicted and confirmed: pushing `8ec77190c` (a twatch
ticket-text fix) preempted the first `full`-on-HEAD run in **5h13m** at ~207 of
2765 jobs. Abort count 52 → 53. The run had been reachable at all only because
pin verify had retired minutes earlier — see
`bug-t-the-push-rate-starves-breadth-coverage-entirely`.

## Why a habit is not the fix

The obvious answer is "check `.testmgr/watch.json` for `phase: testing, fast:
false` before pushing, and batch tooling commits". That is what T is doing now,
and it is exactly the shape this repo keeps rejecting: **a property that holds
only because an agent remembered is a habit, not a property.** It also fails
open — a T agent that does not know the rule, or a cron-driven face 2, pushes
straight through it.

## Shape (sketch, not prescribed)

Ordered cheapest first; 1 and 2 are worth having regardless of the others.

1. **Refuse to be silent about it.** `tools/sync.sh` (or a pre-push check) warns
   when an idle-phase full tier is in flight, naming the sha and the job count
   at risk. Cheap, no behaviour change, converts an invisible cost into a
   visible one.
2. **Make the cost recoverable rather than avoided** — this is
   `bug-t-the-push-rate-starves-breadth-coverage-entirely` shape 2
   (resumable backfill). A resumable run turns a T push from "discard 207 jobs"
   into "pause 207 jobs", which dissolves this ticket rather than managing it.
   **If shape 2 lands, close this as fixed-by.**
3. **Distinguish tool changes that can move a verdict from ones that cannot.**
   A change to ticket-*text* generation (`file_cascade_ticket`, `write_report_md`
   prose) cannot change any job's result; a change to tier composition or
   timeouts obviously can. Tempting, and probably wrong to attempt: the
   classification is a judgment call the watcher would get silently wrong in the
   direction of under-testing, which is the one direction that matters. Recorded
   so the next person does not re-derive it as new.

## Gate

Whatever lands: a devtest driving `make_preempted` over a scratch bare repo with
a `tools/`-only commit, asserting the chosen behaviour explicitly — so the rule
is a guard rather than a note.

*Filed by Track T (plexus-T) 2026-08-19, after doing exactly this to itself and
predicting it in the ticket before confirming it.*

---

## Update 2026-08-19 (plexus-T): option 2's premise was false, and is now repaired

This ticket says *"if shape 2 lands, close this as fixed-by."* Shape 2 **had**
landed — `e2449adc5`, before this ticket was even filed — and it did nothing.
Over its entire life the watcher saved 9 partials worth 1520 jobs and carried
**zero**. There was one partial slot, and `resume_arg()` deleted a partial
belonging to other work instead of declining it, so the very push this ticket is
about destroyed the partial as well as the run.

So the fix-by condition was never met, and reading "shape 2 shipped" as "option 2
is available" would have closed this ticket on a mechanism that did not exist —
the same substitution of *code landed* for *effect measured* the breadth ticket
made. Root cause and fix:
`bug-t-a-saved-partial-is-evicted-by-the-next-run-of-different-work`.

**What is true now:** partials live in a keyed store and provably survive an
interleaved run of different work (devtest). **What is not yet true:** that a
resumed slice has actually carried anything on the live watcher. That is one
number — `carried_runs` leaving zero — and it is this ticket's fix-by condition
as much as the other's. Until then option 1 (warn on a T push while a full tier
is in flight) is still worth its low cost, because it is the only one of the
three that does not depend on a measurement nobody has taken yet.

---

## RESOLUTION 2026-08-26 — dissolved, but NOT by the mechanism this ticket
## nominated

The ticket says: *"If shape 2 lands, close this as fixed-by."* Shape 2 landed on
2026-08-19 (`e2449adc5`). **Closing on that would have been wrong**, and the
numbers say why: over the mechanism's whole life, **73 of 22,280 saved
job-results were ever reused — 0.33%** (`saved_partials 83, carried_runs 3,
superseded 70`).

Not because resume is broken. `superseded: 70` is the explanation and it is
correct: a partial is keyed on `(sha, tier)`, and on abort the watcher
re-targets to the **new** HEAD — so the partial it just saved belongs to a sha
nobody will ask about again. **Resumability can only pay where the same
`(sha, tier)` is retried**, and a push-driven ladder almost never retries one.
That is a structural ceiling, not a defect. It is why "a T push turns *discard
207 jobs* into *pause 207 jobs*" did not happen: the next run was not for that
sha.

### What actually dissolved it

**A commitment point** (`572524c7c`, 2026-08-25): an idle-ladder breadth run
that is `full_commit_secs` (default **60s**) in stops accepting preemption, and
a *reserved* breadth run (`7457f6aee`) commits at **zero** seconds, because a
reservation exists precisely for the case where pushes never stop.

So the premise — *"any T tooling push aborts an in-flight idle-phase full tier
and discards 100% of it"* — is now false except inside a 60-second window at the
very start of an idle-ladder run. The motivating incident, a push landing at
~207 of 2765 jobs, is far outside it and would survive today.

Outcome, measured across 3,828 run records: breadth full-to-full gap **median
1.3h over the last 24h** (worst 3.1h), against the 5h13m drought that opened
the sibling ticket. See `bug-t-the-push-rate-starves-breadth-coverage-entirely`
for the dated before/after.

### Where resume DOES pay, so it is not written off

The one phase that retries a single sha: **pin verify**. It is deliberately left
fully preemptive — the commitment point is breadth's alone — and it relies on
resume instead, which works for it exactly because the key is stable. The live
log: `kept 432 decided job(s) from the aborted full run`, and
`resume: partial accepted — 56 job(s) already decided against this exact
binary`. Resume was built for the wrong ticket and turns out to be load-bearing
for a different one.

### Shape 1 was not implemented, deliberately

*"`tools/sync.sh` warns when an idle-phase full tier is in flight."* With the
commitment point in place, the cost it would make visible is a 60-second window
on one phase — and a warning that fires on a cost that is usually zero trains
people to ignore warnings. If breadth staleness regresses, this is the cheap
thing to add back.

### And the ticket's own instinct was right

> a property that holds only because an agent remembered is a habit, not a
> property.

That is exactly why it should not have closed on shape 2: the property it wanted
— *a T push does not cost breadth* — was never delivered by resume, and only
looked delivered because `carried_runs` had left zero. **A close condition can be
about the wrong subject just as easily as a test can.**

## Log
- 2026-08-26 — measured; closed on the commitment point, not on shape 2.
- 2026-08-26 — resolved, commit 7b76b6049.
