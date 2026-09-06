---
slug: bug-t-progress-near-devtest-measures-a-ticket-summary-length-so-the-board-turns-the-tool-devtest-red
track: T
prio: 45
type: bug
status: backlog-tools
owner:
blocked-by: []
summary: "`tools/progress_near_devtest.py`'s `a slug reaches its own ticket with a usable score` builds its corpus from `progress.Board()` — the LIVE board — and asserts a floor of 0.10 over the 25 first open tickets. The quantity it actually measures is the LENGTH OF ONE TICKET'S `summary:` FIELD: `feature-dynamic-compiler-tables` scored 0.138 at 125 summary-tokens (`2ecd771d9`), 0.098 at 247, and 0.089 today at 292, with the tool's code unchanged throughout. So `make tools-devtest` is RED fleet-wide because a session did what CLAUDE.md tells it to do — keep a ticket's summary true — and no tool defect exists. Needs a calibration DECISION (fixed synthetic corpus for the metric properties, live board only for the corpus-shape assertions; or an IDF/length normalisation; or a floor expressed relative to the corpus rather than absolute), which is why this is filed rather than fixed: bumping the threshold would re-green it until the next long summary and would delete the evidence that the instrument is aimed at the wrong thing."
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

**That is now the sharper half of the fork.** A fixed synthetic corpus fixes both directions
at once — reproducible numbers, and a population chosen deliberately rather than by whatever
`Board()` enumerates first. Raising the floor fixes neither: the outlier moves out of the
slice on its own and the check goes quiet without anything being repaired.

## The inference is still flagged, and now for a MEASURED reason

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
