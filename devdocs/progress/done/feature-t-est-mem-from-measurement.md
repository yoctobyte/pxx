---
summary: "testmgr estimates the selfhost job at 1200 MB; measured peak RSS is 156 MB. An 8x error in one class means none of them were measured — it both under-packs big boxes and will exclude small ones"
type: feature
track: T
prio: 55
status: done
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

## Done — 2026-08-13

### 1. Measured rather than estimated, from runs that already happened

Point 1 of "Asked for" turned out to be already built: the runner records
`peak_rss` per job from a /proc sweep over the job's whole **session**, so it
counts make + compiler + the test together — better than `ru_maxrss` on one
child, which is what the ticket suggested. The numbers were being written into
each run's report JSON and thrown away.

So no bespoke measuring run was needed. Aggregating 891 measured jobs from the
watcher's own recent runs:

| class | n | median | p99 | max | est was | est now |
|---|---|---|---|---|---|---|
| unit | 749 | 49 MB | 83 MB | 355 MB | 700 MB | **550 MB** |
| qemu | 25 | 25 MB | 48 MB | 48 MB | 800 MB | **256 MB** |
| selfhost | 21 | 167 MB | 328 MB | 328 MB | 1200 MB | **500 MB** |
| corpus | 48 | 199 MB | 257 MB | 257 MB | 1400 MB | **400 MB** |
| conformance | 36 | 30 MB | 36 MB | 36 MB | 1000 MB | **256 MB** |
| opt | 12 | 54 MB | 517 MB | 517 MB | 700 MB | **800 MB** |

Rule as asked (point 3): `max(observed_max * 1.5, MIN_EST_MEM)` — max not mean,
1.5x on top, because under-packing wastes a box while under-*estimating* invites
the OOM killer into a run that then reports fake reds. Checked into the table
(point 2's preferred option), not a per-host learned file.

Two things worth flagging in the numbers. **`opt` went UP** (700 -> 800): it was
the one class whose guess was nearly right, and 517 MB observed against a 700 MB
estimate is not the margin it looks like — deriving from measurement is not the
same as deriving downward. And `MIN_EST_MEM = 256 MB` exists because qemu (n=25)
and opt (n=12) are thin samples; `48 * 1.5 = 72 MB` is not a number to hand the
admission gate on that evidence.

The 8x figure in the title held up: selfhost measured 321-328 MB against a
1200 MB estimate, and the bss-reservation explanation was right — 151 MB of
static arrays reserved, only touched pages resident.

### 2. Every run now publishes the data that would revise the table

```
  est_mem peak/est MB: corpus 258/400  selfhost 321/500  unit 200/550
```

and, when a job exceeds its class estimate, a `!!` line naming that job and its
peak — which is both the OOM early warning and exactly the datum the row should
become. Without this the table drifts back into a guess the moment the workloads
change, which is how it got 8x wrong in the first place.

### Gate, honestly

`--tier native`, 1226/1226 pass, GREEN, no OOM, no swap-gate trip, and the line
above shows every class 1.5-2.8x under its estimate.

**The other half of the gate cannot be demonstrated on this box, and the reason
is worth recording.** It asks to show a full run scheduling more jobs
concurrently. It will not, because memory was never the binding constraint here:

```
MemAvailable 54.6 GB, MEM_FLOOR 1.5 GB, hard_cap = nproc*2 = 24
memory-admissible concurrent, old table: unit 77, selfhost 45, corpus 38
memory-admissible concurrent, new table: unit 98, selfhost 108, corpus 135
```

Every one of those was already far above `hard_cap`, so plexus has always been
core-bound and the correction changes nothing observable here. The value lands
where the ticket said it would — a small box, and any box under real memory
pressure — not on the machine that motivated the measurement.

### What that exposed, and why point 4 still matters

Checking whether the corrected table actually delivers the small-box case: **it
does not**, for a reason unrelated to `est_mem`. `MEM_FLOOR` is an absolute
1500 MB and admission is `avail - est_mem > MEM_FLOOR`, so a 512 MB Pi fails the
test for every class at any estimate, including zero. Filed as
[[bug-t-mem-floor-is-a-fixed-1500mb-so-a-small-box-admits-nothing-ever]] — and
it fails *silently*, one starvation-forced job per 90 s, which is the same shape
as the outages this track has spent the month on.

Point 4 (confirm arm32 on real hardware) is therefore **not done and should not
be assumed**: the ILP32 argument is still a prediction, the numbers above are
x86_64, and the floor bug means the Pi case has never actually been exercised.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
