---
track: T
prio: 35
type: bug
blocked-by: []
summary: "`tools/csmith_fuzz.py`'s PXX_TIMEOUT bucket fires on a fixed wall-clock limit, so a program that merely runs slower than the limit is filed as a HANG. Seed 90044 sat in that bucket for a run: pxx took 18s where gcc took 6.9s, both finished, and both agreed. The bucket name sends the reader looking for an infinite loop."
status: done
---

# The csmith harness files "slower than the limit" as PXX_TIMEOUT

Found 2026-08-15/16 while working [[feature-c-csmith-differential-fuzzing]].

## What happened

Seed 90044 came back as `PXX_TIMEOUT`, whose documented meaning is "pxx's
binary hung". It did not hang:

```
./t_pxx   18.2s     (pxx, default -O2)
./t_gcc    6.9s     (gcc -O0)
```

and the checksums agree exactly. The program is a compute-heavy csmith
generator; pxx is ~2.6x slower on it than gcc -O0, and the harness's fixed
limit sits between the two numbers.

`PXX_TIMEOUT` is the right bucket for a genuine spin and the wrong one for
this. The cost is a reader's time: a hang means a control-flow bug and gets
chased like one, and the finding is preserved with a REPRO.md that says
"-O0 hung".

## Fix shape

The harness already RUNS the gcc build first and therefore already knows how
long the oracle took. Scale the limit off it — something like
`max(fixed_floor, k * gcc_seconds)` — and split the bucket:

- `PXX_TIMEOUT` — did not finish even at the scaled limit (a real hang).
- `PXX_SLOW` — finished, checksums agree, but took more than k× the oracle.
  Worth recording as a Track O data point rather than as a defect; a csmith
  program is pathological by construction, so a ratio here is a hint, not a
  regression.

Keep the seed and t.c for both, exactly as now — the reproduction is the
valuable part either way.

## Note

This is a TOOL fix and stays in Track T (`tools/csmith_fuzz.py`). The 2.6x
itself is not a T item and is not filed as one: it is one pathological
program, not a measurement of anything.

## 2026-08-16 — FIXED, both halves of the fix shape

`run()` now returns elapsed seconds for every invocation — free, and the oracle's
cost is what everything below is scaled off. Then, exactly as this ticket
proposed:

- **The limit is scaled off the oracle**: `max(fixed_floor, TIMEOUT_FACTOR *
  gcc_seconds)` with `TIMEOUT_FACTOR = 20`. The `--timeout` value stays as the
  FLOOR, so a millisecond-fast oracle cannot squeeze the budget to nothing.
- **The bucket is split.** `PXX_TIMEOUT` now means "did not finish even at the
  scaled limit", and says so in the detail rather than the bare "-O0 hung" that
  sent the reader after a control-flow bug:

  ```
  -O0 did not finish in 138.0s (20x the gcc oracle's 6.9s)
  ```

- **`PXX_SLOW`** is the new bucket: finished, checksums agree, but took more
  than `SLOW_FACTOR = 4` x the oracle. Its detail says in as many words that it
  is a Track O hint and not a defect, and the `.c` plus REPRO.md are saved for
  it exactly as for every other bucket.

Two details worth recording because they are easy to get wrong:

1. **The slow check runs AFTER both comparisons.** A wrong answer beats a slow
   one — a miscompile must never be filed as a performance note.
2. **A short oracle makes the ratio meaningless.** A 5 ms oracle turns an
   ordinary 200 ms run into "40x slow". `SLOW_MIN_SEC = 1.0` requires the pxx
   side to be slow in absolute terms before the ratio is allowed to mean
   anything.

And `PXX_SLOW` still counts toward the "N/M agreed with the gcc oracle" line —
agreeing is its definition, so leaving it out would have made adding the bucket
look like a correctness regression in the report.

### Verified

- **Seed 90044, the seed that filed this ticket: `ok`.** It was `PXX_TIMEOUT`.
- Every branch exercised deterministically with a stubbed `run()`:

  | case | bucket |
  | --- | --- |
  | fast, agrees | ok |
  | 2.6x — this ticket's case | **ok** |
  | 6x and over 1s | **PXX_SLOW** |
  | 40x but only 0.2s (timer noise) | ok |
  | never finishes | **PXX_TIMEOUT** |

- Real sweep, 12 seeds from 90040: 9 agreed, 3 skipped, no findings, no
  regressions.

The 2.6x itself remains unfiled, per this ticket's own closing note: one
pathological program is not a measurement of anything.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
