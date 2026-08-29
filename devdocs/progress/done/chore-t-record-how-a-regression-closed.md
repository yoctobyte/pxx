---
track: T
prio: 30
type: chore
blocked-by: []
summary: "reg_open closes an entry when a job stops being red, and the record cannot say whether it stopped FAILING or stopped RUNNING — a closure by skip is indistinguishable from a closure by pass. Additive `closed_by` on the closure, losing nothing, and it is what makes decide-t-should-a-skip-close-an-open-regression answerable with data instead of on principle."
status: done
owner: pxx-a5
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

---

## Resolution — 2026-08-28, Track T (pxx-a5)

### The cost was not hypothetical, and it is worse than "a missing field"

This was filed as instrumentation for
[[decide-t-should-a-skip-close-an-open-regression]], on the honest footing that
no cost had ever been observed. Implementing it found one, in
`close_stub_tickets()`:

```
"`%s` passes at %s (tier %s); it was red at %s."
```

Written **unconditionally** into the ticket the watcher retires. So a regression
that closed because its job stopped *running* got a permanent written claim that
it **passed** — the false-fixed claim, in prose, in `done/`, which is precisely
where a finding stops being looked at. The ticket said the frequency was
unmeasurable; it did not notice that the record was also actively wrong wherever
it did fire.

That does not answer the Track U question — it does not tell us how *often* —
but it raises what a single occurrence costs, and it is the kind of thing the
decision should be re-read with.

### What changed

`closure_status(r, authoritative, gone)` → `"pass"` / `"skip"` / `"gone"` /
`"mixed"`, stamped onto each closed entry as `closed_by` **beside the `reg_open`
filter that closed it** — not re-derived by the consumer, which could otherwise
disagree with the predicate that actually fired.

`"gone"` outranks the others: an entry closed because its job no longer exists
did not pass and did not skip. `"mixed"` exists for a cascade closing on some
passes and some skips, which must not read as a clean pass.

The auto-close line now says what the close is evidence **of**, and for a skip
says plainly what it is **not** evidence of (*"the job stopped running here, NOT
that the bug is fixed"*). An entry with no `closed_by` — written by an older
watcher — falls through to the original wording rather than to a hedge.

### What did NOT change, deliberately

`reg_open()`'s verdict is untouched. A skip still closes an open regression.
**Whether it should is the Track U decision, and this chore must not
pre-empt it by making the behaviour quietly stricter** — that would be the
policy change smuggled behind a bug fix that the split was made to prevent. A
devtest asserts `reg_open` still closes on skip, precisely so a future edit
cannot drift the policy under cover of the instrument.

### Verified by mutation, not by reading

Per this ticket's own gate note. Four breaks, each caught:

| break | guards |
| --- | --- |
| **A** drop the skip branch (skip reported as pass — the defect) | 2 |
| **B** make the pass wording hedge too (the over-correction) | 1 |
| **C** `PASSLIKE = ("pass",)` (the chore silently deciding the U question) | 1 |
| **D** cascade with one skip reads as a clean pass | 1 |

Break B is the one worth keeping: if *every* close hedges, the honest ones stop
carrying information and readers learn to skim the line — the fix defeating
itself by being applied everywhere.

### Gate

17 devtests covering `reg_open` / `close_stub` / `open_regressions` / `PASSLIKE`
/ `diff_jobs` green, including `twatch_close_stubs_devtest`,
`devtest_stub_lifecycle` and `devtest_skip_semantics` — the three nearest
neighbours — plus the new 10-case guard and the reader-discipline check. The
86-file family was not swept (see
[[chore-t-tools-devtest-is-one-job-that-runs-86-guards]]); the covering subset
is the risk surface.

### Note for the coordinator

Second ledger field in two days (`never_passed` was the first). Additive,
absent-means-unknown. No lane reads these yet, but they are accumulating.

## Log
- 2026-08-28 — resolved, commit 0fc679056.
