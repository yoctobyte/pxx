---
slug: bug-t-nothing-checks-that-two-hosts-run-the-same-suite
title: "Nothing checks corpus parity across hosts, so one box's green is a smaller suite than another's"
track: T
type: bug
prio: 60
status: backlog
found: 2026-08-30
found-by: frank-user, on the owner's question about what "all tests passed" covers
summary: "plexus's watcher tree was missing five library_candidates that seven's had (html5lib, reportlab, rtl-generics, tinycss2, webencodings), so every Track T run on plexus silently omitted those jobs and reported GREEN. Fetched by hand 2026-08-30; nothing prevents it recurring or detects it today. A skip is PASSLIKE, so a corpus a box never fetched is invisible in the verdict — and the asymmetry is only findable by diffing two hosts by hand, which nothing does."
---

# Nothing checks that two hosts run the same suite

## The measurement

`library_candidates/` in the watcher trees, 2026-08-30:

| host | entries | missing vs the other |
| --- | ---: | --- |
| seven (`~/trackt-watch`) | 25 | — |
| plexus (`~/trackt-watch`) | **20** | `html5lib`, `reportlab`, `rtl-generics`, `tinycss2`, `webencodings` |

Four of the five are the NilPy corpus stack. **Every Track T run on plexus
silently omitted their jobs and reported GREEN.** Fixed by hand with
`tools/install_lib_candidates.sh`; both trees are at 25 now. Nothing stops it
recurring, and nothing would have told us.

## Why it is invisible, and why that is not a bug in the skip design

A skip is deliberately **passlike** (`PASSLIKE = ("pass", "skip")`), and
`testmgr.py` argues the case well: a RED for an absent corpus is *strictly worse*
than a SKIP, because it masks a future real red. That reasoning is correct and
this ticket does not propose changing it.

The report is honest too — it prints its own banner:

> **COVERAGE: N job(s) DID NOT RUN on this box** ... they are scored passlike, so
> they are invisible in the verdict above — a `RED` here speaks for the jobs that
> ran, not for the suite.

and `skip_holes` is in every `runs-*.ndjson` row. **The instrument reports the
hole. The gap is that nothing compares two hosts, and nothing consumes the count
when a green is cited as proof.** 1.4% of GREEN runs in the archive (44 of 3253)
carry at least one hole.

## Why it matters now, specifically

The owner ruled 2026-08-30 that **self-host + all tests passed = proof**, and the
reasoning is that the compiler and target set are complex enough to constitute
one. That is sound *exactly to the degree the suite actually runs.* A `-O2`
promotion citing a green from a box missing five corpora is citing a smaller
suite than the reader will assume, and nothing in the citation says so.

## What to build — three, in order of value

1. **A parity check.** `tstate` already knows what each host ran. Compare the job
   sets of the last full run per host and report any job present on one and
   absent on another. This finds the class, not the instance.
2. **A proof-grade flag on the run row.** `skip_holes == 0 and tier == "full"`
   is the property a promotion should cite. Name it once in the archive rather
   than have every consumer re-derive it — and re-deriving it is what nobody did.
3. **A fetch-on-start for the watcher**, or a loud refusal to start with an
   incomplete corpus. Prefer loud refusal at *start*, not per job: the per-job
   skip is correct behaviour and should stay.

## What NOT to do

**Do not make a corpus-absent skip red.** `testmgr.py` already carries that
argument and it is right. The fix is *knowing which suite you ran*, not failing
runs for a box's fetch state.

## A note for whoever takes this

The `opt` tier is disjoint from `full`, so `-O3` is untested by full runs
entirely — the report says so in a second banner. That means promoting a pass
from `-O3` to `-O2` **increases** the coverage it gets, since the full tier then
exercises it at the default level. Worth stating in the promotion ticket: the
promotion is not only a speed change, it moves the pass into the suite that
actually runs.
