---
slug: bug-t-progress-near-devtest-measures-a-ticket-summary-length-so-the-board-turns-the-tool-devtest-red
track: T
prio: 45
type: bug
status: done
owner:
blocked-by: []
summary: "RESOLVED 2026-09-06 by the fork this ticket recommended: the METRIC properties moved to a fixed written corpus (`tools/progress_near_corpus.py`, 25 hand-written documents) and the BOARD properties stayed on the board. The devtest no longer reads any ticket's `summary:` at all. A fresh measurement removed the last argument for the cheap options: before any change, the failing probe was no longer `feature-dynamic-compiler-tables` at 0.089 but `feature-pascal-corpus-expansion` at **0.076**, which frankZ had measured at 0.113 hours earlier — IDF is computed over the corpus, so filing or closing ANY ticket moves EVERY score. A threshold bump needs both the outlier's identity and its score to be stable and neither is; a fixed corpus needs neither. The corpus is a control only while the two REJECTED metrics still fail against it, asserted in the same run: Similarity floor 0.286 / saturation 0.137, Jaccard floor 0.071 (fails the floor), containment saturation 0.800 (fails saturation). HEAD LENGTH IN THE CORPUS IS LOAD-BEARING: a first draft with one-line heads scored 0.364 under Jaccard, so the control PASSED and the guard above it had silently stopped guarding. A working `progress.py` change (cap the summary at 1200 chars inside `_ticket_head` only) was built, measured to green the job, and DISCARDED — it is one step sideways from the option this ticket already declined, because it still changes what `near` ranks and it was decided by a devtest; `near` was checked and is not broken."
---

# `near`'s devtest fails on board prose, not on the tool

## The measurement

`main()` builds `heads = {slug: _tokens(_ticket_head(t))}` from a live `progress.Board()`.
`_ticket_head` is `slug + title + summary` — so a ticket's **summary length** is the
denominator of every score in that index. The failing check asserts that the worst
self-score across the first 25 open tickets is `>= 0.10`.

Measured 2026-09-06, one slug, tool code identical at all three points:

| summary tokens | self-score | verdict |
| --- | --- | --- |
| 125 (`2ecd771d9`) | 0.138 | green |
| 247 | 0.098 | red |
| 292 (today) | 0.089 | red |

`feature-dynamic-compiler-tables` is a heavily-worked Track A row whose summary was kept
accurate across a night of ten commits. **Nothing about `near` changed.**

## Why this is a defect in the devtest and not in the board

A tool devtest that reads the live board **cannot distinguish a broken tool from a long
ticket**, and it fails in the direction that reads as tool breakage. The red is currently
the only red in `tools/*devtest*.py`, so `make tools-devtest` is red for every session,
which is the state in which nobody reads a red.

It also drifts silently: the same named failure printed 0.098 earlier the same day and
0.089 hours later. **A check whose number moves while its subject is untouched is
reporting about something else.**

## The fork (why this is not a unilateral fix)

The devtest has two KINDS of assertion mixed into one corpus:

1. **Properties of the METRIC** — a slug reaches its own ticket; a short unrelated query
   does not saturate a long document. These want a **fixed synthetic corpus** with hand-
   written long and short documents, so the numbers are reproducible and a red means the
   metric changed.
2. **Properties of the BOARD** — the known duplicate pair is still present. These
   legitimately want the live board, and they are the ones that would go stale in a
   fixture.

Splitting on that line is the recommendation. The alternatives, both cheaper and both
worse: raise the floor (re-greens until the next long summary, and erases the finding),
or normalise the score by document length (changes what `near` ranks, which is a
behaviour change to a tool people use, decided by a devtest — the tail wagging).

## Do not "repair" it by shortening the summary

The summary is long because it is TRUE, which is what CLAUDE.md requires of it. Trimming
a ticket's summary to green a tool devtest would be fixing the measured object to suit
the instrument.

## It is a FIFTH cause of `tools-devtest#00`, not a separate matter

`make tools-devtest` globs `tools/*devtest*.py` (Makefile, the `tools-devtest` recipe), so
this case is inside the job that
`chore-t-tools-devtest-00-is-six-reds-with-four-causes` [T p75] censused on 2026-09-03. It is
**not** one of that ticket's six — those are `sync_pending_commit_devtest`,
`devtest_sync_fold`, `exit_observable_devtest`, `test_wiring_gate_devtest`,
`testmgr_hardcoded_tmp_devtest` and the bench fingerprint. This one appeared **after** the
census, when the summary it measures crossed the floor.

Noted on that ticket's summary rather than in its slug: `six-reds-with-four-causes` was true
on 2026-09-03 and repairing it in place would make a dated claim look freshly measured.

## The calibration data, and it changes the fork (frankZ, 2026-09-06)

frankZ reproduced 0.089 for `feature-dynamic-compiler-tables` exactly, then measured the
population this check is drawn from:

- **623 open tickets, 600 scoreable, exactly ONE below the 0.10 floor.**
- **Median 0.401** — four and a half times the floor.

**So the metric is healthy and this is a single outlier, not a population trend.** That
removes one option outright: there is nothing wrong with the score, and normalising by
document length would be changing a ranking that works to green a devtest.

**And it surfaces the failure direction nobody had looked at.** `probes` is `[:25]` — the
first 25 open tickets **in board order**, 4% of the board — and it **happens to contain the
global minimum**. That is luck. The second-worst is `feature-pascal-corpus-expansion` at
**0.113**, outside the slice and close to the floor.

> **This check has BOTH failure directions.** It reds on board prose, as filed — and it will
> go **GREEN while the identical condition exists**, the moment the long-summary ticket falls
> outside the first 25. A guard whose population is a 4% slice chosen by board order is not
> measuring the property it names; it is sampling.

**One caveat frankZ attached to its own measurement, and it matters for exactly one of the
options.** The slice property was measured on this checkout's board only, so *"the outlier
happens to be inside the first 25"* is **one observation, not a stable fact** — it moves
whenever a ticket is filed or closed. A **fixed corpus does not need either number to be
stable.** A **threshold bump needs both to be**, and neither is.

**That is now the sharper half of the fork.** A fixed synthetic corpus fixes both directions
at once — reproducible numbers, and a population chosen deliberately rather than by whatever
`Board()` enumerates first. Raising the floor fixes neither: the outlier moves out of the
slice on its own and the check goes quiet without anything being repaired.

## CLOSED — measured at the sha the RED report was produced from

The inference ("the `#00` job on seven reds for this reason too") is now a measurement, and
the way it closed is worth more than the answer.

**It did NOT close by reading the report.** `tstate/` **is** in this checkout, at
`devdocs/progress/tstate/reports/` — frankZ's `find -maxdepth 4` had answered about a
shallower tree and we both read "no rows" as "no archive". Reading it settled nothing:

```
- tools-devtest#00
  - `tools-devtest: tools/twatch_timeout_verdict_devtest.py | tools-devtest: tools/twatch_toolchain_devtest.py | tools-devtest: tools/twatch_verify_request_devtest.p`
```

> **The `near:` field is a fixed-width TAIL OF THE JOB'S CAPTURED OUTPUT, not a failure
> list.** For this job it caught three of the Makefile's per-file PROGRESS lines — printed
> before each devtest runs, for files that may well have passed — and names no failure at
> all. It is also cut mid-word. So absence from that row is uninformative in both directions,
> and **a reader who takes it as "the failing devtests" gets a confident wrong answer**, which
> is the more dangerous half. `progress_near_devtest` sorts before `twatch_*` in the glob, so
> it could never appear in a tail regardless of whether it failed.

**It closed by measuring the failing condition at the tested tree instead.** The report
`20260906T031318Z-92ba89e-seven.md` is `verdict: RED` at
`92ba89e82a4aa2dc98b68f97f22e4aba7855d0f7`. Scoring this ticket's own subject from the board
**as of that sha**:

```
at the TESTED sha 92ba89e: 292 summary-tokens, score 0.089   (floor 0.10)
```

So the guard fails at the exact tree seven tested, and `make tools-devtest` globs
`tools/*devtest*.py`. **This is one of the reasons `tools-devtest#00` was red on that run** —
not the only one, since the `#00` census already names four others.

**The method, which generalises:** when the report cannot say WHICH check failed, do not
argue about the report — **reproduce the failing condition at the sha the report names.** That
converts an unanswerable question about an instrument into an ordinary measurement about a
tree.

## The earlier state of this flag, kept because the reasoning is the reusable part



frankZ looked in the archive — which **is** in this checkout, at
`devdocs/progress/tstate/reports/`, contrary to what both of us believed. `progress_near_devtest`
appears in exactly **two** reports, `20260830T023316Z` and `20260831T062413Z`, and in **none**
of the recent ones.

**That does not close the inference.** The `tools-devtest#00` row in the current report is
**truncated mid-word** — it ends `twatch_verify_request_devtest.p` — so the row **cannot
enumerate which devtest failed**, and absence from it is uninformative in both directions.

> **A truncated list answers "not present" for everything past the cut.** The lookup ran, the
> instrument did not error, and the result is still not evidence. The flag stays, with a
> measured reason replacing a missing one.

**One caveat on scope, and it is the only claim here I did not measure.** The three numbers
above were measured on this checkout with `python3 tools/progress_near_devtest.py`. That the
`#00` job on seven is also red for this reason follows from the glob and from the corpus
being the committed board, but **no tstate report was read** — `tstate/` is not in this
checkout. If someone with the archive can confirm it, that closes the inference.

## RESOLVED 2026-09-06 — the fixed corpus, and a fresh measurement that removes the last argument for the cheap options

**Taken as filed: the metric properties moved to a written corpus, the board
properties stayed on the board.** `tools/progress_near_corpus.py` is 25
hand-written documents. `progress_near_devtest.py` now scores
`a slug reaches its own ticket` and `a short unrelated query does not saturate`
against it, and both positive controls (Jaccard, containment) run against the
same corpus. The known-duplicate-pair rows still read the live board, because
they are about the board.

**The measurement that arrived while this was being fixed is the reason not to
argue the alternatives again.** frankZ's calibration was *"exactly ONE below the
floor, median 0.401"*, with `feature-pascal-corpus-expansion` second-worst at
**0.113** and outside the slice. Re-measured today, before any change:

```
FAIL  a slug reaches its own ticket with a usable score
      — worst 0.076 for feature-pascal-corpus-expansion
```

**The outlier changed identity and the second-worst got worse, not better.**
`feature-dynamic-compiler-tables` at 0.089 was not the subject any more;
`feature-pascal-corpus-expansion` had gone from 0.113 to 0.076 with the tool
untouched. IDF is computed over the corpus, so filing and closing tickets moves
EVERY score — which is precisely why frankZ's own caveat said the slice property
is *"one observation, not a stable fact"*. A threshold bump needs both numbers
stable and neither is. The fixed corpus needs neither.

### What makes the corpus a control and not decoration

**The two REJECTED metrics must still fail against it**, in the same run, or the
corpus has quietly become agreeable. Measured, and these numbers cannot drift:

```
                   self-score floor    saturation vs the long doc
  Similarity           0.286                   0.137
  Jaccard              0.071                     -      <- fails the floor
  Containment            -                     0.800    <- fails saturation
```

**Head LENGTH in that corpus is load-bearing, not padding**, and this is the
part a tidy corpus gets wrong. `_ticket_head` is slug + title + summary, and
Jaccard's documented failure is that the union becomes the whole ticket and a
short query rounds away. A first draft with one-line heads scored **0.364** under
Jaccard — comfortably above the floor, so the control PASSED and the guard above
it had stopped guarding. The heads carry realistic multi-sentence summaries for
that reason alone.

### The option I built first and threw away

I had a working change to `progress.py`: cap the summary at 1200 characters
inside `_ticket_head` only, leaving `_ticket_doc` whole. It greened the devtest.
**It is the option this ticket already declined**, one step sideways — it does
not normalise by length, but it does change what `near` ranks for any ticket
whose summary is long, and it was decided by a devtest. Checked before
discarding it, on the outlier's own words: `near` returns sensible neighbours
today at every rank that matters. **There is nothing wrong with the score.** The
change is not in the tree.

**Do not "repair" this by shortening a summary** still stands, and now costs
nothing: the guard no longer reads any ticket's summary at all.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit f98e1105b.
