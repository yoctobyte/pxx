---
track: T
prio: 45
type: bug
summary: "MEM_FLOOR is a fixed 1500 MB and admission requires `avail - est_mem > MEM_FLOOR`, so any box with under ~1.7 GB available admits NO job of any class, forever — the scheduler does not report a small box, it silently never starts. Fixing est_mem does not reach this."
---

# `MEM_FLOOR` is absolute, so a small box can never admit any job at all

- **Type:** bug (scheduler admission) — Track T (`tools/testmgr.py`)
- **Found:** 2026-08-13 while resolving
  [[feature-t-est-mem-from-measurement]], checking whether the corrected
  `est_mem` table actually delivers that ticket's second motivation.
- **It does not**, and this is why.

## The mechanism

```python
MEM_FLOOR = 1500 << 20          # never admit below this MemAvailable
...
return avail - job.est_mem > MEM_FLOOR
```

`MEM_FLOOR` is an absolute quantity on a machine whose total memory is not.
On the 512 MB arm32 Pi that [[feature-t-est-mem-from-measurement]] proposes as
a native oracle, `MemAvailable` is perhaps 400 MB, so for **every** class:

```
400 MB - est_mem  >  1500 MB      ->  false, for any est_mem >= 0
```

The comparison cannot be satisfied even by a job estimated at zero bytes. So
correcting `selfhost` from 1200 MB to a measured 500 MB — which that ticket
did, and which was right on its own terms — changes nothing for the case that
motivated it. The small box still admits nothing, of any class, ever.

## Why it will not look like this from the outside

It does not error. `admit()` simply returns false every time, the queue never
drains, and `admit_forced()`'s starvation path (`STARVE_GRACE`, 90 s of no
progress) is what eventually pushes a job through. So the observable behaviour
on a small box is **a run that appears to work but proceeds one job per 90
seconds, forever**, with no line anywhere saying "this box is below the floor".
That is the same shape as the outages this track has been fixing all month:
every liveness signal healthy, no useful work happening.

## Fix shape

Make the floor relative to the box, keeping the absolute value as a cap so
nothing changes on the machines it already suits:

```python
mem_floor = min(MEM_FLOOR, int(MemTotal * SOME_FRACTION))
```

Two things to settle before writing it, neither of which should be guessed:

1. **The fraction.** The floor exists to leave the kernel and the rest of the
   box room to breathe, and what "enough" means is not proportional in the same
   way on 512 MB as on 64 GB. Measure on a real small box rather than picking a
   number that looks reasonable.
2. **Whether a below-floor box should run at all.** A Pi that can technically
   compile but spends the run in reclaim produces slow, contended, and
   possibly *wrong* timing data — and it is a watcher, so its output is
   verdicts other tracks trust. "Refuse loudly, with a reason" may be the
   better answer than "admit carefully". That is arguably a Track U call about
   what the fleet is for.

**Whichever way it goes, the silence is a bug independently of the policy.** A
box that cannot admit its own smallest job should say so at startup, next to
the `tier=... jobs=N cap=N` banner, not discover it 90 seconds at a time.

## Not urgent

No box in the fleet is currently below the floor (plexus: 54.6 GB available,
admitting 38-212 concurrent by memory against a `hard_cap` of 24 — memory is
not the binding constraint there at all). This is filed because the
small-box case is a stated goal of the est_mem work and would fail silently
the first time it was tried, on hardware the user already owns.
