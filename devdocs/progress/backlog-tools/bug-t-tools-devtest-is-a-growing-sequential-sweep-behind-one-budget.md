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
summary: "`tools-devtest#00` runs every `tools/*devtest*.py` script one after another in a single job, so its wall time is the SUM of a set everyone is encouraged to add to — and its budget is a constant. Measured: 207s over ~130 scripts (2026-09-01), 354.5s over 149 (2026-09-06). That is 1.71x in five days against only 1.15x more scripts, so the scripts are getting heavier faster than they are getting more numerous and no constant survives it. The class budget was raised 600 -> 1200 in a new `guards-py` class as the immediate fix, but that number is sized to OBTAIN a completing observation under tier contention, not derived from one: the job has still never completed inside a full tier (`n:0`), and 600.1s is a CENSORED reading that establishes only a lower bound on the contention factor (>= 1.69). The structural fix is to SHARD the sweep the way `test-c-conformance` is sharded — N jobs the scheduler can pack, each with a small budget that stays meaningful as the set grows, and each naming which scripts it ran. That also fixes a second thing the single job cannot do: it reports one verdict for 149 scripts, and its stored `reason` is a fixed-width tail that has named passing progress lines rather than the failure."
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
