---
summary: "testmgr 'hangs' = starvation + invisible systemd-scoped orphans; make it self-heal"
type: bug
prio: 75
---

# testmgr "hangs": it is STARVATION, and the cause is orphans pstree cannot show

- **Type:** bug (Track T — tools & testing)
- **Status:** working
- **Owner:** claude (frank2 session, 2026-07-13)
- **Found:** 2026-07-13, user report: "trackt/testmgr does not run as expected, it seems
  to be able to hang. re-running does not properly kill or check running daemons.
  actually (other shell session) we have that issue right now."

## Symptom
`tools/testmgr.py --tier quick` sitting for 25+ minutes. A *quick* tier. Re-running
makes it worse, not better. Nothing obviously wrong; nothing in `pstree`.

## What it actually is (three bugs, one chain)

**1. It is not hung — it is STARVED.** `admit_ok()` gates every job on *global machine*
state: memory PSI, swap floor, `MemAvailable`. None of those are about *us*. So when the
box is loaded **by something else**, no job is ever admitted, `self.running` stays empty,
and the scheduler sleeps in its loop until the global 3600s deadline. Confirmed live:
`testmgr: admission held — swap low (992 MB free)` repeating, 1 of 11 jobs done.

Backpressure is only sound while something of *ours* is running — that job will finish
and free memory, so waiting is productive. With nothing running there is nothing to wait
for and no reason the next tick differs from this one. **That is a deadlock, not
backpressure.**

**2. The cause: orphaned runs that `pstree` structurally cannot show.**
`reexec_scoped()` re-execs testmgr inside a transient **systemd scope** (that is what
applies the memory cap). systemd then *adopts* the process:

```
PID 2602226  PPID 1548 (systemd --user)
cgroup: /user.slice/…/app.slice/run-r42ec7a70….scope
```

So a running testmgr **leaves the launching shell's process tree**. It is not a child, not
a job. Therefore:
- it is invisible to `pstree` / `jobs` — a live run looks like nothing is happening
  (this is exactly what the user hit: *"i don't see testmgr in pstree"*);
- **killing the shell, or the agent session, does not kill it.** It runs on, detached, to
  its deadline.

Orphans therefore accumulate silently across sessions. Each holds memory → PSI rises →
**new runs fail admission**. The orphans are the *cause*; the starvation is the *symptom*.
Observed on the box: three concurrent detached runs (two from finished sessions).

**3. No mutual exclusion, and a build race that fakes a self-host regression.**
Two testmgr runs could not see each other, so a re-run piled onto the load starving the
first — *"re-running does not properly kill or check running daemons"* and *"it hangs"*
are the same bug from two ends. Worse: `build_compiler()` shells out to `make`, whose
`BUILD_COMPILER`/`VERIFY_COMPILER` default to the **fixed global paths**
`/tmp/pascal26-build` / `-verify`, shared by *every clone on the box*. Two runs in
different checkouts write the same two files, and the self-host fixedpoint step then
`cmp`s one clone's binary against the other's:

```
/tmp/pascal26-build /tmp/pascal26-verify differ: byte 97, line 1
```

A **fabricated self-host regression**, on the one gate that blesses the stable binary.
Reproduced while testing the lock. (This is the non-job half of
[[chore-makefile-testtmp-parameterize]]: testmgr already rewrites `/tmp/` for JOB
scripts, but `make` runs outside that rewrite.)

## Fix (landed)
1. **Forward-progress guarantee** (`admit_forced()`): nothing running + work queued + no
   progress for 90s ⇒ force ONE job through the gates, loudly. Then stay in **degraded
   mode** — force back-to-back, one at a time — until a job passes the real gates on its
   own. (First cut re-served the full 90s grace before *every* forced job: 90s × 11 jobs
   ≈ 16 min, i.e. most of the hang again. Degraded mode fixes that.) A hostile box now
   makes the run *slow*, never *stuck*.
2. **Run lock** (`.testmgr/run.lock`, pid + heartbeat): a second run refuses instead of
   piling on; `--force` kills the live one and takes over. Liveness = live pid **and**
   fresh heartbeat — a pid alone gets reused, and a wedged run that stopped scheduling
   should not block others forever. Heartbeat is written by a **daemon thread**, not the
   scheduler loop, because `build_compiler()` runs for minutes before the loop starts and
   a lock that goes stale mid-build invites another run to kill us.
3. **Box-wide discovery + a conservative reaper**: `--status` scans `/proc` and lists
   every testmgr on the box with its repo, tier and age — the only way to see what
   `pstree` cannot. `--kill-orphans` reaps them, but **"detached" is not "orphaned"**:
   every scoped run is detached by design, including the twatch daemon's and other
   agents' live work. So it kills only runs whose *own repo's lock has stopped beating*,
   with an age floor (`--older-than`, default 30m). A reaper that kills healthy work is
   worse than the leak it fixes.
4. **Private build paths**: testmgr passes `BUILD_COMPILER=/tmp/pascal26-build-<repo-tag>`
   (etc.) on the make command line — plain `:=` vars, so no Makefile edit, and the Track A
   `$(TESTTMP)` sweep stays its own ticket.

## Verification
Real hostile box (nine concurrent testmgr processes from other agents/sessions):
`--tier quick` **11/11 pass, 247s wall**, with the self-heal firing live
(`STARVED 90s … forcing test-quick#00`). Before the fix, the same conditions produced the
25-minute non-run the user reported. Unit tests cover: force-only-when-deadlocked,
never-during-real-backpressure, degraded-mode rate limiting, degraded clears on recovery,
lock refuses live / reclaims wedged / reclaims dead-pid, and the reaper keeps live runs.

**A bug the tests found in the fix itself:** `reap_stale()` originally did
`killpg(getpgid(pid))`. If the target shares our process group (a testmgr started plainly
from a shell, no setsid), that group is the *shell's* — so it would kill the shell, the
agent session, and every sibling. The first run of the lock test SIGKILLed itself proving
it. Now: group-kill only a process that leads its own group; otherwise kill the single pid.

## Log
- 2026-07-13 — filed and fixed in the same session (Track T owns testmgr). Diagnosis came
  from the live box, not from reading code: the user's *"i don't see testmgr in pstree"*
  was the decisive clue — it is what exposed the systemd-scope reparenting, which turned
  "why does it hang" into "why do orphans accumulate", which is the real bug.
