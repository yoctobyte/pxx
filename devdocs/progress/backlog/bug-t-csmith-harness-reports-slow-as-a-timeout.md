---
track: T
prio: 35
type: bug
blocked-by: []
summary: "`tools/csmith_fuzz.py`'s PXX_TIMEOUT bucket fires on a fixed wall-clock limit, so a program that merely runs slower than the limit is filed as a HANG. Seed 90044 sat in that bucket for a run: pxx took 18s where gcc took 6.9s, both finished, and both agreed. The bucket name sends the reader looking for an infinite loop."
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
