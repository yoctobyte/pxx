---
summary: "idle fuzz/bench leave ~130MB/hour in /tmp; on xeon /tmp is tmpfs, so it eats RAM the scheduler is counting on"
type: bug
track: T
prio: 70
---

# Idle fuzz/bench leak `/tmp`; on a tmpfs box that is RAM, not disk

- **Type:** bug (Track T tooling) — filed by `claude@borg` 2026-08-01, from
  xeon's report that "tmpfs kept filling up".
- **Lane:** T's own tooling ⇒ xeon's to fix.

## Measured on xeon (read-only inspection, nothing deleted)

`/tmp` on xeon is **tmpfs, 31 G**. Leftovers after ~10 hours of overnight
running (oldest `Jul 31 19:42`, newest `Aug 1 05:57`):

| prefix | count | total |
|---|---|---|
| `tbench-*` | 20 | **768 M** |
| `pasmith.*` | 54 | 333 M |
| `pxx_*` | 46 | 186 M |
| `twatch-report-*` | 5 | 504 K |
| **`testmgr-scratch-*`** | **0** | — |

≈ **1.29 GB in ~10 h ≈ 130 MB/hour**, and it is monotonic.

## The diagnosis is slightly different from "testmgr doesn't clean up"

**`testmgr-scratch-*` is clean — zero left behind.** The main runner disposes of
its scratch correctly. The leak is in the **idle work paths** that run
continuously when the box has nothing else to do:

- `idle_fuzz` → `pasmith.*` (54 dirs — one per fuzz round, never removed)
- `idle_bench` → `tbench-*` (20 dirs, and the largest single consumer)
- plus fixed-name build outputs under `pxx_*` that are written, used, and left

So it is not the tier machinery; it is precisely the *endless* background work,
which is also why it only shows up on a box left running overnight.

## Why this is worse than disk pressure

On a tmpfs box, `/tmp` **is RAM**. testmgr's own admission control reads
`MemAvailable` and refuses to admit jobs below `MEM_FLOOR`, kills and requeues
above `PSI_KILL`, and sizes cgroup limits from `MemTotal`. Leaked tmpfs pages
therefore:

1. shrink the memory the scheduler believes it has,
2. push it toward degraded-serial admission and PSI kills,
3. and do so **gradually**, so the symptom is "the matrix got slower and flakier
   overnight" rather than "the disk filled".

That is a much more confusing failure than ENOSPC, and it lands on the box the
whole fleet now depends on for its gate.

## Fix direction

- Have `pasmith`/`fuzz.sh` and the bench harness clean their working dir on
  exit, including on failure — a `trap` on EXIT, not a tidy-up at the end of the
  happy path (a fuzz round that crashes is exactly the round that leaves a dir).
- Keep the last N rounds if they are wanted for triage, but **bounded** — prune
  oldest beyond N rather than keeping everything.
- Sweep on daemon start for the box's own stale prefixes, the way
  `--kill-orphans` already handles stray processes; the same age-floor idea
  (`--older-than`) applies.
- Consider making the idle paths honour a tmpfs-aware budget: on a tmpfs `/tmp`,
  cap total scratch and skip a round rather than eat the scheduler's headroom.

## Not done here

Nothing was deleted — `tbench-8m_d11ig` was 4 minutes old at inspection, so a
live run was using it. Cleanup on that box belongs to whoever holds T, and
should be a `trap`, not a cron `rm -rf`.
