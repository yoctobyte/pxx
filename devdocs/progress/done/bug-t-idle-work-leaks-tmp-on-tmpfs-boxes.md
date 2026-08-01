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

---

## FIXED — `5767ea61f` (claude@xeon, 2026-08-01)

Your diagnosis was right and it split into three causes, not one:

| leak | why | fix |
|---|---|---|
| `tbench-*` (768 M / 20) | `mkdtemp`, never removed | `atexit` rmtree |
| `pasmith.*` + `pasmith-check.*` (333 M / 54) | same, both call sites | `atexit` rmtree |
| `pxx_c_conformance.<pid>` (186 M / 46) | **had a correct `trap ... EXIT` already** | trap widened to `EXIT INT TERM`, plus pid-reap in the sweep |
| per-job log dirs (392 M / 128) | bounded by age only | now bounded by count too (newest 40) |

`atexit` rather than `try/finally` throughout: every one of these call sites has
early `return`s, and a `finally` around the whole function would have missed
them.

**The conformance one is the interesting case.** It looked correct in review —
the trap is right there at `run_c_conformance.sh:74` — and it still leaked 46
dirs, because testmgr SIGKILLs its own over-budget jobs and **a trap never runs
on SIGKILL**. Widening to `INT TERM` catches the signals that can be caught; the
rest is reaped by pid in `sweep_orphan_tmp()`, where liveness is the pid and it
does not matter how the round died. Worth remembering as a general rule here:
on this box a cleanup trap is a best-effort optimisation, never the guarantee.

Idle scratch is age-reaped at **2 h** — those dirs carry no pid, so age is the
only liveness proxy, and 2 h is far past the longest bench round (~3 min).

### Verified

- All eight sweep paths against fabricated dirs: dead-pid conformance reaped,
  **live-pid conformance kept**, dead-pid scratch reaped, old idle reaped, fresh
  idle kept, count cap holds at 40.
- A real `python3 tools/pasmith_run.py --seed 1` — 13 workdirs before, 13 after,
  none leaked. *(This line was eaten by backtick command-substitution in the
  commit message; recorded here instead.)*
- `/tmp` on xeon went **3.1 G → 1.5 G** with the daemon still running.

### Deliberately NOT done

Your fourth suggestion — a tmpfs-aware budget that skips an idle round rather
than eating scheduler headroom — is not implemented. With the leaks closed the
steady state is bounded by construction (age + count), so a budget would be
guarding against a condition that no longer arises. Worth revisiting only if
`/tmp` climbs again with everything above in place.

## Log
- 2026-08-01 — resolved, commit 5767ea61f.
