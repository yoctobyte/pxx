---
summary: "Track T is becoming multi-host with DIFFERENT PURPOSES per box — xeon runs the matrix, arm32/arm64 rPis exist only as native oracles against xeon's QEMU — but profiles express resource ceilings, not purpose, and nothing compares two hosts' results"
type: feature
track: T
prio: 65
---

# Host ROLES: the matrix beast vs the native-only arm oracles

- **Type:** feature (Track T topology) — **Track T**
- **Opened:** 2026-08-01, recording an intended topology that is currently
  undocumented.

## Intended topology

| host | hardware | role |
| --- | --- | --- |
| `xeon` | 12-core, ample RAM, Ubuntu 26.04 | **the matrix.** Full tiers, all cores, cross targets under QEMU, idle fuzz/opt/bench. |
| `borg` | dev-adjacent | existing watcher |
| arm64 rPi | crippled | **native oracle only.** Runs aarch64 tests NATIVELY. |
| arm32 rPi | crippled | **native oracle only.** Runs arm32 tests NATIVELY. |

The point of the rPis is **native vs QEMU differential**: xeon already runs the
arm targets under emulation (`CLASS_WEIGHT` has a `qemu` class), and a real ARM
box says whether a QEMU result is the truth or an emulator artifact. Their job
is *not* to grind full suites all day — they are slow, and a full matrix on a
Pi would take longer than the answer is worth.

## What already exists (do not rebuild it)

- `trackt setup` has a first-run **role-profile wizard** with three profiles —
  `dedicated` / `limited` / `restricted` (`tools/trackt.py:588-660`) — writing
  `max_cores` and `max_mem_mb` into the clone's `twatch.conf`.
- Per-host conf already carries `tier` and `fast_tier`, and the full phase
  accepts `none`, so "fast phase only" is expressible today.
- Per-host tstate state and reports are already keyed by host.

**Naming note:** the launcher is `trackt` (repo root) + `tools/trackt.py`.
There is no `trackt.sh` — worth stating because it gets referred to that way.

## What is missing

1. **Profiles express RESOURCE CEILINGS, not PURPOSE.** `restricted` means "use
   half the cores and a fraction of RAM" — an rPi set to `restricted` still
   works through a *full tier*, just slowly, which is precisely the behaviour
   not wanted. A role needs to say **which job classes this box exists to run**
   (e.g. "native aarch64 jobs only; never corpus, never fuzz, never opt"), not
   merely how hard to push. Suggested shape: a `jobs`/`classes` allowlist in the
   conf, plus a `native-oracle` profile that sets it.

2. **Nothing compares two hosts.** tstate is per-host, and a verdict is
   published per host+sha. The entire value of a native ARM box is
   *host A native vs host B QEMU on the same sha+job* — that comparison does not
   exist. Without it a Pi just re-reports what xeon already said, and the
   differential has to be done by eye.

3. **The topology is undocumented**, which is why this ticket exists. It belongs
   in `devdocs/dev/` alongside the Track T notes once settled.

## Landmine this topology walks straight into

The rPis will run **a different distro again** (Raspberry Pi OS vs Ubuntu 26.04
vs the dev box's 24.04). Cross-distro assertion coupling has already produced
one permanent phantom RED that cost several mis-diagnoses — see
[[bug-t-host-dependent-test-assertions-cross-distro]]. Adding two more distros
multiplies that surface, so that ticket should land *before* the Pis are
enrolled, not after.

## Gate

An arm64 rPi enrolled with a native-oracle role runs only its native job set,
never a full tier, and its results are comparable against xeon's QEMU verdicts
for the same sha without hand work.

## Log
- 2026-08-03 — moved to rainy-day: the arm oracles are aspirational with no
  date and no hardware on hand (user, [[decide-t-queue-scope-2026-08-03]]).
  Kept as the design record for the topology — it is the thing to read when the
  boxes do arrive, and [[bug-t-host-dependent-test-assertions-cross-distro]]
  already installed the triage rule that makes a third distro cheap. Anything
  in here that pays off on xeon ALONE was split out rather than parked with it.
