---
slug: bug-t-nothing-checks-that-two-hosts-run-the-same-suite
title: "Nothing checks corpus parity across hosts, so one box's green is a smaller suite than another's"
track: T
type: bug
prio: 60
status: backlog
found: 2026-08-30
found-by: frank-user, on the owner's question about what "all tests passed" covers
summary: "plexus's watcher tree was missing five library_candidates that seven's had, so every Track T run on plexus silently omitted those jobs and reported GREEN. Fetched by hand 2026-08-30; nothing prevents it recurring or detects it today. AMENDED the same evening — the acceptance criterion is capability x job, NOT job: a second parity gap was measured where both hosts run the SAME job (csmith-fuzz#arm32) and one claims an ILP32 oracle while the other does not, so job list, count and verdict all agree. A job name is a promise, not a description of what ran, and a job-set diff cannot see it. Fix is persistence, not a new prober: probe_oracle already computes the vector and drops it — emit it into the runs-<host>.ndjson row. Read the amendment before implementing."
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

---

## THE ACCEPTANCE CRITERION IS capability × job, NOT job (frankT + frank-user, 2026-08-30 evening)

**A job-set diff — the obvious fix, and the one I agreed to — cannot see the
second half of this bug.** Measured tonight while clearing a red T guard.

`tools/csmith_target_devtest.py` asserted flatly that this box has no ILP32
oracle because `gcc -m32` compiles but does not link. That is true on the box it
was written on. On plexus `gcc -m32` **links**, and `probe_oracle("arm32")`
returns `cc=['gcc','-m32'], kind=datamodel`. So:

- both hosts run `csmith-fuzz#arm32`;
- one **compares ILP32 checksums against an oracle**, the other silently does
  not;
- the job list, the job count and the verdict are **identical on both**.

**A job name is a promise, not a description of what ran** (frank-user).
`csmith-fuzz#arm32` names the INPUT. Both hosts keep the promise. *The artifact
everyone would compare is the one place the difference is guaranteed to be
absent.*

The parity gap here is a **toolchain capability**, not a corpus, so no census of
`library_candidates` — the thing that found the original 20-vs-25 — would ever
have surfaced it. Guard fixed at `658f78ebc`; the guard is not the bug.

### The cheap implementation, and it is persistence rather than a new prober

**Do not build a capability prober.** `probe_oracle` already computes the vector
and drops it after printing — the same shape as `sync.sh` proving a commit was
on origin and discarding the sha, and as `skip_summary` counting coverage holes
without naming them. Three instances in one day, and in all three the fix was
persistence.

So: **emit the vector into the `runs-<host>.ndjson` row that is already
written**, and the parity check becomes a diff of two rows rather than a new
subsystem. The row construction is a single `json.dumps` in `twatch.py` (near
`skip_hole_jobs`, which was added the same way and for the same reason), so the
schema half is a few lines.

### The one question I did NOT settle, because it has a real cost

**Where the vector is computed, and what it costs per run.** `probe_oracle` does
actual compiles, and the fields that matter beyond it (does `gcc -m32` link,
which `qemu-*` exist, is `fpc` present and with which widestring manager) are
each a small subprocess. Paying that once per run is cheap in absolute terms —
and it lands on the box that is **the binding constraint on sweep rate**, which
this repo has measured as what sets the median-8 commit gap.

Two shapes, and whoever takes this should choose deliberately rather than by
default:

1. **Compute once at watcher START**, cache for the process lifetime, and stamp
   every row from the cache. Nearly free; goes stale if a package is installed
   mid-session, which is exactly how the original 20-vs-25 arose.
2. **Compute per run.** Always current, costs a handful of subprocesses per
   sweep on the constrained box.

My recommendation is **(1) plus a re-probe whenever the clone is re-seeded**,
because the staleness window then matches the window in which the tree itself
could change — but it is a cost decision on shared hardware and it is stated
here rather than made in passing.
