---
summary: "testmgr estimates the selfhost job at 1200 MB; measured peak RSS is 156 MB. An 8x error in one class means none of them were measured — it both under-packs big boxes and will exclude small ones"
type: feature
track: T
prio: 55
---

# `est_mem` is a guess, and the one number we checked was 8x wrong

- **Type:** feature (Track T — scheduler accuracy)
- **Opened:** 2026-08-02 by `claude@xeon`, split out of
  [[feature-t-trackt-setup-autodetect-box-role]], which measured the first
  number while working out whether a 512 MB Pi could self-compile.

## The measurement

`testmgr.py` schedules against a per-class table:

```python
"unit":        {"est_mem": 700 << 20,  "timeout": 90},
"qemu":        {"est_mem": 800 << 20,  "timeout": 240},
"selfhost":    {"est_mem": 1200 << 20, "timeout": 600},
"corpus":      {"est_mem": 1400 << 20, "timeout": 1200},
"conformance": {"est_mem": 1000 << 20, "timeout": 1200},
"opt":         {"est_mem": 700 << 20,  "timeout": 900},
```

Measured peak RSS on x86_64, self-hosted binary at `19ee697d3`:

| workload | est_mem says | actually |
|---|---|---|
| self-compile (`compiler.pas` + all `.inc`, 5.6 MB of source) | 1200 MB | **156 MB** |
| `test/hello.pas` | (unit) 700 MB | **24 MB** |

The fixedpoint compiles twice but *sequentially*, so peak stays ~156 MB rather
than doubling.

The `bss=151388300B` in every build line is a ~151 MB **reservation** of static
arrays, not resident cost — only touched pages land in RSS. That is almost
certainly where the 1200 MB guess came from, and it is why reading the ELF
header instead of measuring gets this wrong in the same direction every time.

## Why it costs something in both directions

- **Big boxes under-pack.** The scheduler admits jobs against
  `avail - est_mem`; at 8x the true cost it leaves most of the machine idle
  while queueing work it could have run concurrently. On the box whose whole
  purpose is the matrix, that is the throughput this quarter's dev-loop work
  is trying to buy ([[meta-t-dev-throughput-and-track-a-t-integration]]).
- **Small boxes get excluded from work they can do.** A 512 MB arm32 Pi is a
  plausible native oracle: ordinary test compiles are ~24 MB and a self-compile
  is ~156 MB, and arm32 is ILP32 so the pointer-heavy structures get *cheaper*.
  At est_mem 1200 MB such a box would never be admitted a selfhost job at all,
  and it would look like a hardware limit rather than a table entry.

## Asked for

1. Measure peak RSS per job class rather than estimating — the runner already
   supervises each job, so `wait4()`'s `ru_maxrss` for the child is free and
   exact, no sampling loop needed.
2. Feed the measurements back: either a checked-in table regenerated from a
   measuring run, or a small per-host learned file. **Prefer the checked-in
   table** — a learned file is per-box state the fleet cannot review, and this
   is exactly the kind of number that should be visible in a diff.
3. Whatever lands must keep a conservative floor: an estimate that is too low
   invites the OOM killer, which is far worse than under-packing. Bias the
   derived numbers upward (say max observed × 1.5) rather than using the mean.
4. Confirm the arm32 figure on real hardware before relying on it — the 156 MB
   is x86_64, and the ILP32 argument is a prediction, not a measurement.

## Gate

Report the per-class measured peak in a run's own header alongside `jobs=N
cap=N scale=N`, then show that a full run on this box schedules more jobs
concurrently at the same or lower peak machine memory pressure. No OOM, no
swap-gate trips.
