---
slug: bug-t-tools-devtest-is-a-growing-sequential-sweep-behind-one-budget
track: T
prio: 60
type: bug
status: backlog-tools
found: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "`tools-devtest#00` runs every `tools/*devtest*.py` script one after another in a single job, so its wall time is the SUM of a set everyone is encouraged to add to, behind a CONSTANT budget. That mechanism is the ticket and it is untouched. THE GROWTH-RATE ARGUMENT THIS SUMMARY USED TO LEAD WITH IS RETIRED: it read 207s/~130 (09-01) and 354.5s/149 (09-06) as 1.71x in five days, and the 09-17 section below already called that a slope drawn partly through a bug (host_dev_lib_skip_devtest.py held a quadratic worth 17 minutes on its own). Re-measured 2026-09-22 on the same box and condition -- 344.0s over 166 scripts, plexus quiet, tree 0e864874e, frozen-tree guard green -- the sweep GAINED 17 scripts and LOST ~11s of wall. THE DECIDING MEASUREMENT THIS TICKET ASKED FOR NOW EXISTS AND IT REFUSES BOTH SPLIT RULES PROPOSED BELOW, WHICH ARE BOTH COUNT RULES: the distribution is extremely skewed -- median 0.22s against a 2.07s mean (9.4x), 131 of 166 scripts under a second summing to 10% of the wall, while the top 8 are 70.2% and the top 1 (fpc_trunk_verdict_devtest.py, 78.5s) is 22.8%. Simulated over the real timings at N=8, a count split spans 11.4s..110.6s and admits no budget that is meaningful for both ends; weight-aware greedy gives 78.5s, and THAT SHARD IS THE ONE HEAVY SCRIPT ALONE. So shard by measured WEIGHT at N=4 (344s -> 86s, 4.0x); past N=6 the heaviest single member binds and wider sharding changes nothing, which makes the next lever that script rather than a bigger N. A weight split needs deterministic assignment or a still_red keyed on shard name stops meaning anything, so the assignment comes from a CHECKED-IN script->weight table -- which is itself a summary of last-known timings and decays silently, mis-balancing shards without reddening anything, i.e. the same object as the stale summary this ticket just had repaired. It therefore carries a refresh design rather than a promise: a devtest reds when any script in the glob lacks a row or any row names a deleted script (so decay is impossible rather than detectable, at devtest speed); each shard prints predicted-vs-actual and reds beyond ~2x (so every tier run re-measures the table for free, and a script growing toward a pathology is visible WHILE it grows); and an absent entry defaults HIGH (p90), because the choice turns on which way the error breaks rather than on accuracy -- under-estimating blows a shard budget and reds something that is not a defect, over-estimating only wastes part of a scheduler slot. THE BUDGET QUESTION IS UNTOUCHED AND THIS MEASUREMENT DOES NOT LICENSE A CHANGE TO IT IN EITHER DIRECTION: it is a quiet-box reading with no tier contention, the job has still never completed inside a full tier (n:0), and 600.1s remains a CENSORED lower bound. The single job also still reports one verdict for 166 scripts, with a stored reason that is a fixed-width tail naming passing progress lines rather than the failure."
---

# `tools-devtest` is a growing sequential sweep behind a constant budget

## The trend, measured

| date | scripts | wall | box |
| --- | --- | --- | --- |
| 2026-09-01 | ~130 | 207s | plexus, quiet |
| 2026-09-06 | 149 | 354.5s | plexus, quiet |
| 2026-09-06 | 149 | **>600.1s, killed** | seven, load 13.8, inside a 4447-job full tier |

**1.71x in five days on 1.15x the scripts.** Adding devtests is not the whole
story — the existing ones are getting more expensive too. A single constant
cannot track that, and the entry that holds it now says so in its own comment.

## Why sharding rather than a bigger number

The budget was raised to 1200 in a new `guards-py` class (`tools/testmgr.py`),
and that is a stopgap with a stated expiry. Three things it does not fix:

1. **The number goes stale on a schedule.** Every raise is calibrated against
   whatever the sweep weighed that week.
2. **One job holds one scheduler slot for up to twenty minutes** inside a tier
   running at cap 38. Sharded, the scheduler packs the pieces and the longest
   piece is ~1/N of the wall.
3. **One verdict for 149 scripts.** The stored `reason` is a fixed-width tail
   of captured output, and for this job it has named three `twatch_*` PROGRESS
   lines — printed *before* each script runs, for scripts that may well have
   passed — cut mid-word. A reader who takes it as the failure list gets a
   confident wrong answer, and a script that sorts early in the glob can never
   appear in it regardless of whether it failed. See
   `bug-t-a-tier-job-identifier-is-a-selector-doing-double-duty-as-a-label`.

`test-c-conformance` is already sharded and `job_selector()` already keeps shard
names verbatim (`if "#shard" in job.name: return job.name`), with a comment
saying why they are stable in a way `src:` cannot be. **The machinery exists.**

## What a shard must carry, or it is worse than the sweep

- **Which scripts it ran**, named, so a red is attributable without a tail.
- **A deterministic split**, so shard N holds the same scripts across runs and
  a `still_red` comparison keyed on the shard name means something. Splitting
  by sorted glob position is deterministic until a file is added; splitting by
  a hash of the filename is stable under insertion. Prefer the latter and say
  which was chosen.
- **The `bench_timing_devtest.py` skip**, which the current recipe carries.

## The measurement to take first

Per-script durations. The sweep prints each filename before running it, so a
single instrumented pass yields the distribution. **If it is flat, split by
count; if one script dominates, splitting by count just moves the problem into
one shard.** Nobody has this yet, and it decides the split rule rather than
being a nice-to-have — 354.5s over 149 is 2.4s mean, and a mean over an
unmeasured distribution is exactly the kind of number that has been wrong all
week.

## Do not

Do not raise the budget again without a COMPLETING tier observation to derive
it from. `600.1s` is censored, not a duration, and the 600 it replaced was
itself derived from an idle box — *"a budget calibrated against a broken run is
a budget that punishes the fix"*, which the class comment recorded before this
happened and which recurred verbatim with "broken" replaced by "unloaded".

## 2026-09-17 — ONE MEMBER OF THE SUM WAS 99.7% OF ONE FILE'S SCAN, and it is gone

`host_dev_lib_skip_devtest.py` -- one script in this sweep -- was taking **over
seventeen minutes on its own** and timing the whole job out at 1200.1s. It now
runs in **4.8s**. The cause was a quadratic `^\s*uses` under `re.M` in
`testmgr._USES_RE`, where one source (`compiler/builtin/pylib.pas`) accounted
for 194.241s of a 194.8s total across 1902 files; see
[[bug-t-host-dev-lib-skip-devtest-outgrew-its-budget-and-times-out-the-whole-guards-job]].

**THIS DOES NOT CLOSE THIS TICKET AND THE ARGUMENT IS UNCHANGED.** The wall time
is still the SUM of a set everyone is encouraged to add to, and the budget is
still a constant; that a single member happened to hold a 1082x pathology says
nothing about the next one. What HAS changed is the pressure: the immediate
cause of the current red is fixed, so the sharding work is no longer racing a
tier that cannot complete.

**AND THE NUMBERS IN THE SUMMARY ABOVE ARE NOW STALE IN A WAY THAT MATTERS.**
207s / 354.5s were measured 2026-09-01 and 09-06, BEFORE this pathology grew
into the set. Any growth-rate argument built on those two points now has a third
point that is not on the same curve, because one member's cost was a defect
rather than a trend. **Re-measure the sweep before quoting 1.71x in five days as
evidence for anything** -- it was honest when written and it is now a slope
drawn partly through a bug.


## 2026-09-22 — THE PER-SCRIPT DISTRIBUTION, WHICH THIS TICKET NAMES AS "THE MEASUREMENT TO TAKE FIRST". IT DECIDES THE SPLIT RULE, AND IT REFUSES BOTH CANDIDATES OFFERED ABOVE

**Population, tree, box and instrument, because a bare count is not re-derivable
by anyone including the same instrument.** Population is the RECIPE's, read off
`Makefile:39528` rather than guessed: `tools/*devtest*.py` less
`bench_timing_devtest.py` = **166 scripts**, and that count is written into the
output file beside the rows. Tree `0e864874e`, no modified tracked files,
`compiler/pascal26` = `1e5dd067455ed4fa`. Box **plexus, 12 cores, idle, no tier
contention** — the same box and the same condition as the two clean rows in the
table above, which is why they are comparable. Instrument: a standalone loop
replicating the recipe, `date +%s.%N` either side of each `python3`, one sample
per script and no repeats. `tools/frozen_tree_guard.sh` armed for the whole run
and GREEN afterwards, so the verdict is attributable to one tree.

**Corroboration the run did not need but has:** total measured **344.0 s**
against the full sweep's **343 s** taken separately the same night. Two
independent runs, 1 s apart.

### It is not flat. It is not close to flat.

| | |
| --- | --- |
| total / scripts | 344.0 s over 166 |
| **mean** | **2.07 s** |
| **median** | **0.22 s** |
| p90 | 2.92 s |
| max | 78.5 s |
| min | 0.066 s |

**The mean is 9.4x the median.** This ticket's own warning — *"2.4 s mean, and a
mean over an unmeasured distribution is exactly the kind of number that has been
wrong all week"* — was correct, and the 2.07 s I could have quoted off the sweep
describes almost nothing in the set.

**131 of 166 scripts (79%) run in under a second and sum to 35.9 s — 10% of the
wall.** The other way round: **the top 8 are 70.2% of the wall**, the top 3 are
43.4%, and the top 1 is 22.8%.

| s | script |
| --- | --- |
| 78.5 | `tools/fpc_trunk_verdict_devtest.py` |
| 37.3 | `tools/fpc_oracle_wide_devtest.py` |
| 33.5 | `tools/progress_stale_edge_devtest.py` |
| 33.2 | `tools/testmgr_pin_built_devtest.py` |
| 20.4 | `tools/sync_pending_commit_devtest.py` |
| 14.9 | `tools/progress_orphan_fragment_devtest.py` |
| 12.3 | `tools/fuzz_compare_key_devtest.py` |
| 11.3 | `tools/testmgr_tmp_var_devtest.py` |

### SO SPLIT BY WEIGHT, NOT BY COUNT — AND BOTH RULES THIS TICKET PROPOSED ARE COUNT RULES

Above it offers *"sorted glob position"* and *"a hash of the filename, stable
under insertion"*, and prefers the latter. **They differ only in WHICH scripts
land together; both assign an equal COUNT per shard, and on this distribution
that is the property that fails.** Simulated at N=8 over the real timings:

    count-split (either rule)     weight-aware, longest-first greedy
      shard 0  110.6 s / 21         shard 0   78.5 s /  1
      shard 1   18.6 s / 21         shard 1   37.9 s /  6
      shard 2   11.4 s / 21         shard 2   37.8 s / 19
      shard 3   46.5 s / 21         shard 3   37.9 s / 21
      shard 4   73.1 s / 21         shard 4   37.9 s / 29
      shard 5   22.5 s / 21         shard 5   37.9 s / 30
      shard 6   17.8 s / 20         shard 6   37.9 s / 30
      shard 7   43.5 s / 20         shard 7   37.9 s / 30

**Count-split's makespan is 110.6 s and its shards span 9.7x** — so a small
budget "that stays meaningful as the set grows" cannot be set: it is either too
loose for shard 2 or it kills shard 0. Weight-aware gives **78.5 s**, and the
useful part is WHY: that shard is `fpc_trunk_verdict_devtest.py` **on its own**.

### AND THAT IS THE CEILING. SHARDING WIDER THAN ~4 BUYS NOTHING

Makespan cannot go below the heaviest single member, so the lower bound for any
split is `max(heaviest, total/N)`:

| N | lower bound | total/N | binding |
| --- | --- | --- | --- |
| 2 | 172.0 s | 172.0 | the sum |
| 4 | 86.0 s | 86.0 | the sum |
| 6 | **78.5 s** | 57.3 | **the heaviest script** |
| 8 | **78.5 s** | 43.0 | **the heaviest script** |
| 12 | **78.5 s** | 28.7 | **the heaviest script** |

**N=4 weight-aware is the whole win: 344 s -> 86 s, a 4.0x cut.** Past N=6 the
scheduler is packing around one script and the extra jobs are free only in the
sense that they change nothing. So the sharding work should land at **N=4, split
by measured weight**, and the next lever after that is not a bigger N — it is
`fpc_trunk_verdict_devtest.py` itself.

**A weight split needs the weights to be DETERMINISTIC across runs or a
`still_red` comparison keyed on the shard name stops meaning anything** — which
is this ticket's own requirement above, and it is the real cost of preferring
weight to hash. So: a **checked-in table** of script -> weight, used to assign
shards, so the assignment is a reviewed artefact rather than a function of last
run's timings.

#### AND THAT TABLE IS THE SAME OBJECT AS THE SUMMARY THIS TICKET JUST HAD REPAIRED, SO IT NEEDS THE SAME TWO THINGS

A `script -> weight` table is **a summary of last-known timings**. It decays
silently as scripts change, and a stale weight mis-balances the shards
**without reddening anything** — the no-signal failure, which is the one this
repo keeps paying for. Proposing it without a refresh rule would be filing the
defect I had just finished removing from this ticket's own frontmatter. What it
needs is what every other guard here needs: **what regenerates it, what
TRIGGERS that, and what an absent entry defaults to.**

**TRIGGER 1 — a missing entry is a RED at devtest speed, not a silent default.**
A devtest asserts that every script in the recipe's glob has a table row and
that every table row names a script that exists. That makes the decay
impossible rather than detectable: **you cannot add a devtest without adding its
weight row**, the red arrives in seconds, and the fix is one line. It also
catches the mirror — a row left behind by a deleted script, which quietly
reserves budget in a shard forever.

**TRIGGER 2 — the shards re-measure the table every time they run, for free.**
Each shard already knows its own wall time. Have it print predicted-vs-actual
and red when they diverge beyond a factor (start loose, ~2x). This is the part
that cannot go stale by neglect, because **every tier run is a fresh
measurement of the table's accuracy** and nobody has to remember to regenerate
anything. It is also the only instrument that would have caught
`host_dev_lib_skip_devtest.py` growing from 4.8 s toward seventeen minutes
*while it was happening* rather than when it started timing the job out.

**THE DEFAULT FOR AN ABSENT ENTRY IS PESSIMISTIC, AND THE REASON IS THE SHAPE OF
THE FAILURE, NOT THE ACCURACY OF THE GUESS.** The two obvious choices are both
wrong and wrong differently: **zero** lands a new script free in the heaviest
shard, and **the mean** gives it 2.07 s, which this measurement shows is the one
value almost nothing in the set has (median 0.22 s). Neither is defensible on
accuracy. But the choice does not turn on accuracy — it turns on which way the
error breaks:

- **Under-estimate an unknown** → it lands in an already-full shard, that shard
  blows its budget, and the tier reds. **A red that is not a code defect**, and
  it misattributes to whatever else is in that shard.
- **Over-estimate an unknown** → it gets placed early into a light shard, that
  shard runs under-full, and one scheduler slot is slightly wasted. **Nothing
  reds and nothing is misattributed.**

So default to a **high** weight — p90 (2.92 s here) is enough, `max` is
needlessly extreme — and let TRIGGER 1 make the window short. Fail toward a
wasted slot, never toward a spurious red.

**Regeneration is then a deliberate act with a cheap instrument**: the
per-script pass that produced this section is a loop around the recipe's own
glob and takes one sweep's wall time. Re-run it, diff the table, review the
diff. The trade frankuser named is real — determinism costs freshness — and
TRIGGER 2 is what pays for it: the table may be stale, but **how stale is
measured on every run instead of being assumed.**

### TWO ROWS TO CARRY RATHER THAN RESOLVE

- **`host_dev_lib_skip_devtest.py` measures 8.2 s here against the 4.8 s
  recorded on 2026-09-17** after its quadratic was fixed. Both rows are kept
  rather than one replacing the other: they were taken by different instruments
  on possibly different load, mine is a single sample with no repeats, and a
  1.7x gap is inside what one unrepeated sample can produce. **It is not a
  finding and it is not dismissed** — what would settle it is three repeats on a
  quiet box, and the reason to keep it visible is that this is the one script in
  the set already known to have held a 1082x pathology.
- **Single sample, no repeats, quiet box.** Nothing here establishes variance,
  and the contended case is still `n:0` — the job has never completed inside a
  full tier. **This measurement does NOT license a budget change**, in either
  direction; the "Do not" above is untouched and the reading that would settle
  it is still censored.

### Raw data

`perscript.txt`, one `duration rc script` row per script plus a population line
and a `PERSCRIPT-COMPLETE` token, kept in the session scratchpad rather than
committed — it is 166 rows of one box's timings on one night, and the table
above is the part that transfers.
