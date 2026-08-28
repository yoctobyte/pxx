---
track: T
prio: 30
type: chore
blocked-by: []
summary: "reg_open closes an entry when a job stops being red, and the record cannot say whether it stopped FAILING or stopped RUNNING — a closure by skip is indistinguishable from a closure by pass. Additive `closed_by` on the closure, losing nothing, and it is what makes decide-t-should-a-skip-close-an-open-regression answerable with data instead of on principle."
---

# Record HOW a regression closed, not just that it did

- **Type:** chore (Track T tooling, `tools/twatch.py`). Additive; nothing
  changes behaviour.
- **Split out of** [[decide-t-should-a-skip-close-an-open-regression]] on
  2026-08-28, because that ticket was **a decision whose deciding data the same
  ticket proposed to gather** — one work item and one open question wearing a
  single hat. This is the work item. The question stays there.

## What is missing

`reg_open()` closes an entry when the merged status is no longer red. `skip` is
PASSLIKE, so an entry closes identically whether the job **passed** or merely
**stopped running** — and the closure record says only that it closed.

That is the same information gap as
[[bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good]] (fixed,
`0dec0194a`) one level up in the data model, and it is the reason the frequency
of the false close cannot be counted today. It is also why triaging the synapse
range needed a human: the archive records transitions and still-red, so **a skip
and a pass are both simply absent**, at every past sha.

## The change

Record the status that closed the entry — `closed_by: "pass"` vs
`closed_by: "skip"` — on the closure, and carry it into `close_stub_tickets()`
so a retired stub says which happened.

**Strictly additive.** Absent means unknown, exactly like `never_passed`,
`first_seen`, `pin_axis`, `bad_untestable` and `no_testable_change` before it.
No entry is held open that would have closed, and no verdict changes; this is
the same split that fixed the anchor case — separate the two READINGS of `skip`
rather than reclassify the status.

**It is not one of the horns of the decision.** It loses nothing in either
direction, which is precisely why it belongs outside the decision rather than
inside it as an option.

## Why this is worth doing before the decision is made

The decision asks whether a skip should close a regression at all. Both answers
cost something real, so the useful input is **how often it actually fires** —
and that is unmeasurable until the record can tell the two closures apart. This
is the instrument. It is cheap, it is safe, and its value does not depend on
which way the decision goes.

## Note for whoever lands it

Second ledger field in two days (`never_passed` was the first). Tell the
coordinator: no lane currently reads those fields, but they are accumulating and
should be discoverable in one place.

## Gate

Track T's own tooling gate, plus a devtest asserting both closures are
distinguishable — and, per
[[bug-t-a-silent-test-assertion-makes-the-harness-report-the-wrong-thing]]'s
adjacent-instance note, **verify the guard by mutation, not by reading it**:
make a skip-closure record `"pass"` and confirm a guard fires.
