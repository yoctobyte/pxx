---
slug: chore-t-nothing-in-the-matrix-runs-o3-so-no-failures-is-unfalsifiable
title: "-O3 IS swept, by a tier disjoint from every gate — so 70% of shas never see it and no verdict says which"
track: T
prio: 60
type: chore
blocked-by: []
status: working
owner: "pxx-a5"
created: 2026-08-28
summary: "Premise refuted by measurement: optdiff.sh sweeps -O0 against -O2 and -O3 over all 1841 standalone test programs in 12 shards, has run 701 times (most recently today), has gone non-GREEN 30 times with named optdiff shard reds, and four -O3 bugs in done/ came from it. The real gap is narrower and still real: the opt tier is DISJOINT from quick/native/limited/full, runs only as idle watcher work, so only 690 of 2296 gate-verdict shas (30.1%) ever got -O3 coverage and nothing in a sha's verdict says whether it was one of them. Re-scoped to three cheap items. Track O found a real gap in the wrong mechanism."
---

# The premise as filed is false, and the measurement says so

The ticket asked for a four-level agreement harness to be built because
*"testmgr tiers compile at the default `-O`. No job passes `-O3`. Therefore the
matrix has never reported an `-O3` failure — and it never could, for any pass,
however broken."*

Every clause of that is contradicted by the archive:

| claim as filed | measured |
| --- | --- |
| no job passes `-O3` | `tools/optdiff.sh` compiles and runs at `-O2` **and `-O3`**, comparing stdout+stderr+exit code against an `-O0` baseline, over **all 1841** standalone Pascal and C test programs in **12 shards** |
| nothing exercises it | the `opt` tier has run **701 times**, first `2026-07-11`, most recently **`2026-08-28T09:41:46Z`** — today |
| the matrix never reported an `-O3` failure | **30 of 701** opt runs were non-GREEN; `optdiff` shards are named red in **16** of them, `test-opt` in 1 |
| it never could, however broken | `done/` holds four such findings: `regression-optdiff-o3-stack-frame-intrinsics`, `bug-o3-inline-breaks-frame-walk-intrinsics`, `bug-a-aarch64-o3-segfaults-the-compiler-on-an-empty-program`, `bug-o-o3-diverges-on-cmath-sign-bits-and-pascal-hijack` |

The harness this ticket asks to be built already exists, and its
no-external-oracle property — *"the other levels are the oracle, no
expected-output files to maintain"* — is exactly how `optdiff.sh` was designed.
The reasoning in the ticket is sound; it was applied to a mechanism that was
already there.

The testmgr comment above the tier says it in one line:

> `opt`: generate() adds OPT_SHARDS optdiff.sh jobs sweeping EVERY standalone
> Pascal/C test at `-O0` against `-O2` and `-O3` (stdout+rc must match).
> **Idle watcher work, not `full`.**

That last clause is the whole finding.

# The real gap, measured

`covered_tiers("opt")` returns `opt` alone. The tier is **disjoint** from the
nesting chain quick → native → limited → full, and it runs only as an idle
watcher phase (`idle_opt`) against whatever sha happens to be current when the
box is free.

Consequence, from the archive:

- **2296** distinct shas have a gate-tier verdict (quick/native/limited/full).
- **690** distinct shas have an opt-tier verdict.
- **690 of 2296 = 30.1%** of gate-verdicted shas ever got `-O3` coverage.
- **Nothing in a sha's verdict says which 30% it is in.**

So the true statement is not "nobody runs `-O3`" but:

> **A GREEN verdict on a sha is silent about `-O3`. Roughly 7 shas in 10 never
> got that coverage, and the report gives you no way to tell yours apart from
> the 3 that did.**

That is still the same family as the skip-counted-as-pass bug — an absent signal
read as a negative result — but one level further out: the job runs, the tier
runs, and the *attribution to a sha* is what is missing. It is a report-format
and tier-composition gap, which is squarely T's tool.

# What survives from Track O's ask

Three things, all cheap, none requiring a new harness:

1. **`-O1` is genuinely unswept.** The level loop covers 2 and 3 only. O asked
   for agreement across `-O0`/`-O1`/`-O2`/`-O3`, and `-O1` is the one level that
   really has no coverage anywhere in the matrix. Adding it is a one-token
   change; the cost is +50% optdiff wall, which matters because opt already runs
   ~20 minutes per sweep. Size it before doing it — possibly `-O1` over a subset.
2. **Verdict visibility.** A sha's report should state whether `opt` covered it,
   and at which sha the last opt sweep landed. This is the actual fix for the
   thing O correctly smelled: today "no `-O3` failures for this sha" and "opt has
   not visited this sha" *do* produce identical evidence in the report, even
   though they are distinguishable in the archive.
3. **Corpus density, not a new job.** `w2stress.pas` is worth having — but as a
   file in the test corpus, where the existing 12 shards sweep it automatically
   at every level forever, not as a bespoke harness. Track O hands the program
   over; no T machinery is needed to make it swept. This is the cheapest item and
   probably the highest value for the register-pressure campaign specifically,
   since the corpus is broad but not dense in in-place ALU shapes.

# What this does to the -O2 promotion gate

The coordinator made this ticket a precondition on `-O3` → `-O2` promotion. That
precondition is **substantially already met, and was met before the ticket was
filed**: `-O3` is swept over the whole corpus, and the campaign's four landed
passes have been through opt sweeps as ordinary corpus coverage — including the
GREEN 17/17 opt run at `03afd81fd` (1208.8s wall, 12 optdiff shards, 5 test-opt
jobs) that Track T ran this session.

What promotion still lacks is *attribution*: nobody can currently point at a
verdict and say "this sha's `-O3` was swept." Item 2 is what turns that into a
citable fact. Item 3 is what makes the sweep dense where the campaign actually
changed codegen. Neither is a reason to hold promotion indefinitely, and the
"first exposure wearing a promotion's clothes" framing does not survive the
measurement — the passes have had matrix exposure at `-O3`.

**Recommendation to the coordinator: lift the hard precondition, keep item 3 as a
courtesy ask on Track O** (hand over `w2stress.pas`), and let item 2 land on T's
own schedule.

# Boundaries

- Still filed by Track O, still done by Track T; O found a real gap and named the
  wrong mechanism for it. The value of the filing is unchanged — 70% sha coverage
  with no verdict attribution is worth a p60 — and nothing here is a criticism of
  the reasoning, which was correct about the risk and wrong about the inventory.
- No compiler bug here, and T does not fix one if there were.
- The `{$Q+}` FPC-oracle trap the ticket documents is real and correctly
  identified; it does not apply to `optdiff.sh`, which uses no external oracle,
  for exactly the reason the ticket gives.

# Method note

The premise was checked before it was implemented, against the archive rather
than against the ticket's own account of the inventory. The session rule that
caught it: **verify the location/existence claim rather than taking it on
report** — the same rule that found this ticket in `backlog_new/` after the
coordinator's greps missed it. A confident "nothing does X" is a claim about an
inventory, and inventories are cheap to query.

One correction recorded against my own work here: my first archive read reported
the last opt run as `2026-07-31`. The NDJSON archive is not date-ordered across
hosts, and a `tail` of the concatenation is not a chronological tail. Sorting by
`date` gives today. Same failure family as the rest of this ticket — a
convenient read of an inventory, taken for the inventory.
