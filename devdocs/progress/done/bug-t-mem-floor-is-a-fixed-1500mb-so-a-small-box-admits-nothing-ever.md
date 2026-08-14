---
track: T
prio: 45
type: bug
summary: "MEM_FLOOR is a fixed 1500 MB and admission requires `avail - est_mem > MEM_FLOOR`, so any box with under ~1.7 GB available admits NO job of any class, forever — the scheduler does not report a small box, it silently never starts. Fixing est_mem does not reach this."
status: done
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

## DONE 2026-08-14 — the silence is fixed; the policy is escalated

This ticket said it itself: *"whichever way it goes, the silence is a bug
independently of the policy."* That half is done, and the policy half is now
[[decide-t-mem-floor-policy-on-a-small-box]] (Track U) rather than a guess.

`report_mem_floor()` runs next to the startup banner. On a healthy box it says
nothing; on a box that cannot admit its own smallest job it prints the
arithmetic and names what will actually happen:

```
testmgr: !! THIS BOX CANNOT ADMIT ANY JOB — MemAvailable 400 MB, smallest class
            needs 256 MB, floor is 1500 MB
testmgr: !! admission needs avail-est_mem > floor, i.e. 144 MB > 1500 MB, which is
            FALSE for every class (MemTotal 512 MB — the floor is larger than the machine)
testmgr: !! the run will proceed on the STARVATION path only — about one job per
            90s, indefinitely. This is not a hang and not a hardware fault; it is
            the floor.
```

Naming the starvation path matters more than the numbers: the failure mode this
ticket describes is a run that *looks* healthy, so the operator needs to be told
the crawl is the floor rather than a hang or a dying disk.

### The threshold is ~1.75 GB, not "a Pi"

The diagnostic surfaced something the ticket did not: `MEM_FLOOR + MIN_EST_MEM`
is 1756 MB, so a **2 GB machine with 1.6 GB available also admits nothing**.
This was filed about a 512 MB arm32 Pi; a 2 GB box is not obviously affected,
and nobody would work that out from the constant. That is the argument for
printing it rather than documenting it.

### Gate

`tools/devtest_mem_floor.py` — 10 checks: healthy boxes stay silent (including
one byte above the threshold), the 512 MB Pi warns and notes the floor exceeds
the whole machine, the 2 GB box warns *without* that note, a missing
`/proc/meminfo` claims nothing rather than raising a false alarm, and the
smallest class is pinned to `MIN_EST_MEM` so a future `CLASSES` edit cannot move
the threshold silently.

`tools/gate.sh quick` GREEN.

## Log
- 2026-08-14 — resolved, commit aadb064ea.
