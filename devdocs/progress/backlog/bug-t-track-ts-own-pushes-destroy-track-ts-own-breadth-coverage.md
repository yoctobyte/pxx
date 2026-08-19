---
slug: bug-t-track-ts-own-pushes-destroy-track-ts-own-breadth-coverage
track: T
type: bug
prio: 50
status: backlog
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
