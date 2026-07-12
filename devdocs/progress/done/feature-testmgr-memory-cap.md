---
prio: 65  # froze the dev box once (2026-07-12); one hard reset is enough
---

# testmgr: cap its own memory in a cgroup scope + swap-aware admission

- **Type:** feature / robustness — **Track T** (`tools/testmgr.py`)
- **Status:** done
- **Opened:** 2026-07-12, after an opt-tier run wedged the box (hard reset).

## Symptom

An `--tier opt` run (optdiff shards, scratch `/tmp/testmgr-scratch-1821920`)
drove the machine into swap thrash. Journal died mid-write:

```
Jul 12 17:08:30 borg systemd-resolved[1030]: Under memory pressure, flushing caches.
Jul 12 17:08:33 borg systemd-journald[334]: Under memory pressure, flushing caches.
Jul 12 17:08:55 borg systemd-journald[334]: Under memory pressure, flushing caches.
   <log ends — box unresponsive, hard reset>
```

Nothing was OOM-killed. 25 seconds from first pressure to a dead desktop.

## Why nothing saved us

- **Kernel OOM killer never fired**: 1.8 GB of swap was still free, so reclaim
  kept "succeeding" (at disk speed). Livelock, not OOM. The kernel only OOMs
  when reclaim *fails*.
- **systemd-oomd never fired**: it is a *pressure* daemon — needs PSI > 50% for
  20 continuous seconds on `user@1000.service`. The box died inside that dwell
  window, and oomd's own pages were faulting too.
- **testmgr's own guards never fired**: admission (`admit_ok`,
  tools/testmgr.py:535) gates on `MemAvailable - est_mem > MEM_FLOOR (1.5 GB)`.
  `MemAvailable` counts reclaimable page cache and **ignores swap state
  entirely** — sar shows it reading ~10 GB "available" while the box was already
  56% swapped (2.3 GB of 4 GB) and at 97% commit. The watchdog
  (tools/testmgr.py:546) only trips under `MemAvailable < 750 MB`, which under a
  refault storm arrives after the box is already unschedulable.

Secondary: jobs with no learned RSS are charged `est_mem = 32 MB`
(tools/testmgr.py:508). Self-compile and optdiff shards are hundreds of MB, so a
cold metrics store systematically under-charges exactly the fat jobs.

## Fix

**1. Self-scope (the real fix — makes a freeze structurally impossible).**
testmgr re-execs itself into a memory-capped cgroup at startup, so a runaway
job is killed by the kernel *inside the scope* and the desktop never stalls. No
caller-side setup, works for make targets, cron and the twatch daemon alike:

```python
# early in main(), before any job is scheduled
if os.environ.get("TESTMGR_SCOPED") != "1" and shutil.which("systemd-run"):
    os.environ["TESTMGR_SCOPED"] = "1"
    os.execvp("systemd-run", [
        "systemd-run", "--user", "--scope", "--quiet",
        "-p", "MemoryMax=8G", "-p", "MemorySwapMax=1G",
        sys.executable, *sys.argv])
```

Cap should be derived from box RAM (e.g. `min(8G, 60% of MemTotal)`), not
hardcoded. Degrade gracefully when `systemd-run` is absent or the user has no
systemd session (CI containers): skip the re-exec, keep going.

**2. Swap-aware admission.** `admit_ok` must also refuse when free swap is low
or memory PSI is already climbing — `MemAvailable` alone is a broken signal on a
swapping box:

- refuse admission if `SwapFree < 1 GB`
- refuse admission if `/proc/pressure/memory` `some avg10 > 20`
- run the watchdog off the same PSI signal, so it acts while it still can

**3. Honest cold-start estimate.** Raise the unlearned-job `est_mem` default, or
seed it per job class (`CLASSES`), so a cold metrics store doesn't admit a swarm
of self-compile shards at 32 MB apiece.

## Acceptance

- `tools/testmgr.py --tier opt` on a box with a deliberately squeezed swap
  cannot wedge the desktop: the scope's `MemoryMax` kills the offending job, the
  run reports it red/requeued, the session survives.
- Admission refuses to launch new jobs while swap is nearly full or memory PSI
  is elevated; the refusal is visible in the run log (no silent stall).
- `--tier full` stays green; no regression in wall-clock on an unloaded box
  (the scope costs nothing when the cap is never hit).
- Works headless / in CI (no systemd user session) by falling back to the
  unscoped path.

## Notes

Out of scope, host-side (user did these on 2026-07-12): `vm.swappiness=10`
(60 pushed 2.3 GB of idle anon into swap while 11 GB RAM sat free — that swapped
anon *is* the refault storm) and installing `earlyoom` as a system-wide
backstop. Neither belongs in the repo; testmgr must not depend on them.

## Log
- 2026-07-12 — resolved, commit c7b78389.
