# Independent confirmation at `cba854637` — the last full report's three unresolved reds

**Read this as a dated measurement, not as a tier verdict.** It is three jobs run
by one seat on plexus, not a tier run, and it does not substitute for Track T's.

    COMMIT   cba854637
    BINARY   compiler/pascal26 = 3abc191e63139ea6
    SRCHASH  520d4628b1367418 (stamp == tree)
    BUILD    "converged after 1 round(s)" — a real recompute, not the stamp path
    BOX      shared: frank-subcoord's `--tier quick` was running concurrently

Baseline is the newest full-tier report at the time, `6d04b14c` (2026-09-06
18:37:24Z, RED), which was 54 commits behind by the time this ran.

| job | at `6d04b14c` | at `cba854637` |
| --- | --- | --- |
| `test-emit-obj#07` | STILL-RED | **PASS** 2.7s |
| `tools-devtest#00` | **TIMED OUT** | **PASS** 341.0s |
| `test-fpjson#00` | STILL-RED | **SKIP** — corpus absent |

Job keys resolved with `testmgr --tier full --list`, never by counting
occurrences in the Makefile. That distinction cost a wrong exculpation earlier
the same night: `@N` indexes JOBS, not source occurrences.

## `tools-devtest#00` is a third independent number for the cumulative story

341.0s under testmgr, against `CLASSES["guards"]["timeout"] = 600`
(`testmgr.py:365`). Beside `f98e1105b`'s 354.5s and a raw 405.1s loop measured
here earlier, all three sit in the same band below a 600s budget that **rises
monotonically as devtests are added**. Nothing here is a hang.

## The `test-fpjson` row BOUNDS the false-skip rule rather than confirming it

This is the correction worth carrying, and it is against my own sentence.

*"A false skip is worse than a false red — a red is loud and a skip is silent"*
is **not true of this layer**. testmgr is emphatic:

    !! CORPUS MISSING — 1 job(s) will SKIP, not run.
    SKIP     test-fpjson#00   corpus   0.0s
    SKIPPED (did not run; scored passlike, NOT counted as red):
      corpus absent: library_candidates/fcl-json

It says it twice, names the missing corpus, and states that passlike scoring is
not a pass. **At the row level this harness is louder than most reds.**

**Exactly one line is misleading, and it is the one a reader quotes:**
`testmgr: GREEN`. A run whose only job did not run reports GREEN, because
nothing failed. The verdict summarises the jobs that RAN and is read as
summarising the jobs that EXIST.

So the rule needs its scope stated: **the silence is at the VERDICT level, not
the row level.** Where a harness names its skips, the fix is not more warning
text — it is that a verdict computed over the jobs that ran must not be printed
in the same shape as one computed over all of them.

## Four layers of "did not run", assembled from four seats

Only the first appears in a report, and each was found by a seat who could not
see the others.

1. **Named skips with a stated reason** — loud, e.g. this `test-fpjson` row.
2. **`skip_holes`** — counted, but frankH's caveat applies: `skip_holes == 0`
   means no job was skipped for a reason the harness owns, not that every job
   ran.
3. **`test/pascal-conformance/pxx.skip` rows** — frankS: 62 of 92 unmeasured in
   either direction, and no harness classifies them, so `skip_holes` is silent
   about them by construction.
4. **Jobs enrolled in ZERO tiers** — frank-coord-front: `test-esp-bare` and
   `test-esp-softfloat`. Not a skip and not a hole; an absence nothing counts.

**And the two skip defects are different claims that must not be summed.**
frankS's split, which corrects a looser figure that had been circulating:
*false* skips (would pass if un-skipped) measured **0 of 9** on the Pascal wall;
*misdescribed* skips (right verdict, stale reason) **7 of 30 re-measured**, an
upper bound rather than an estimate because people re-measure rows they suspect.
A false skip costs a coverage claim; a stale reason costs the next seat a silent
re-derivation. Reported as one number, "~23% of skip reasons are wrong" would
read as 23% of the wall falsely skipped, **which is measured false.**
