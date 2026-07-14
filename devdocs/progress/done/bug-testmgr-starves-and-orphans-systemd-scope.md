---
summary: "testmgr 'hangs' = starvation + invisible systemd-scoped orphans; make it self-heal"
type: bug
prio: 75
---

# testmgr "hangs": it is STARVATION, and the cause is orphans pstree cannot show

- **Type:** bug (Track T — tools & testing)
- **Status:** done
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

## Follow-on findings (same session, all fixed)
The original three were only the top of the stack. Chasing them on the live box turned
up three more, each bigger than the last:

4. **The swap floor was a permanent lockout, not a safety gate** (d94db8d6). borg had
   8 GB MemAvailable and memory PSI **flat 0.00** — a completely healthy box — yet every
   job was held because free swap was 965 MB against a hardcoded **1000 MB** floor. A 35 MB
   miss. And it never recovers: the used swap is stale anon pages from long-lived desktop
   processes (a leaking browser) that are never handed back. So the gate stayed shut
   *forever* and every run crawled in degraded serial mode — the self-heal (#1) was
   holding a chronic misconfiguration upright. A flat 1000 MB is a quarter of a 4 GB swap
   and a rounding error on a 32 GB one; the floor is now `min(1000 MB, 10% of SwapTotal)`.
   With it fixed, the watcher went from 1 job serial to 7 concurrent, 0% CPU idle.
   **Open:** the user's call is that the swap floor should go away entirely — PSI reads
   the stall directly and a free-swap *level* cannot distinguish leaked browser pages from
   a real refault storm. Not yet done.

5. **"Stop" stopped nothing** (a409c695). twatch's SIGTERM handler only set `STOP=True`,
   and the flag was read *between cycles* — but the daemon spends nearly all its life
   blocked in the wait-loop of a testmgr child with minutes of work left. So `trackt stop`
   waited out the entire gate and then told the user to `kill -9` by hand; its own message
   ("aborts any running gate") was false. The wait-loop now checks `STOP` every second and
   tears the gate down (SIGINT, then SIGKILL); trackt escalates rather than handing the
   user homework, and reaps the orphaned testmgr a SIGKILLed daemon leaves behind.

6. **The watcher was failing to BUILD, not failing to test** (0a3657e1, 0348fae0) — the big
   one. `differ: byte 97` → `make Error 1` → `testmgr: building failed` → `twatch: no report
   (rc=1) — infra problem, not recording a verdict`. **1445 times** in the borg log, long
   predating any of this session's changes. Each one killed testmgr before it ran a single
   job, so the sha stayed untested and nothing went red. *That* is why Track T kept falling
   behind and never reached bench/fuzz.
   Root cause: the `make` rule demands a **one-pass** fixedpoint (seed → stage2 → stage3,
   `cmp`), which only holds if the seed already matches the sources. A watcher hops across
   SHAs with a persistent `compiler/pascal26`, so its seed is stale constantly — making
   this the watcher's *normal* case. Bootstraps have always needed the extra round.
   Fix, and the architectural point the user forced: **"can we get a compiler" and "do these
   sources reproduce themselves" are different questions**, and the Makefile welded them
   together — so the project's most important gate could only fail as an *infra crash*.
   Now: build = infrastructure (converge the bootstrap, no gate semantics); the gate is a
   **job** (`tools/selfhost_fixedpoint.sh`, native/limited/full) that seeds from the
   committed **pinned** stable — hermetic, same answer on every box — and asserts both
   convergence *and* agreement with the binary the suite tests with (the anti-Thompson
   check: a compiler can converge to a *different* self-reproducing fixedpoint depending on
   its seed; both green, one carrying whatever the local binary carried). An unbuildable
   compiler now emits a **RED, bisectable report** instead of vanishing.

## Log
- 2026-07-13 — filed and fixed in the same session (Track T owns testmgr). Diagnosis came
  from the live box, not from reading code: the user's *"i don't see testmgr in pstree"*
  was the decisive clue — it is what exposed the systemd-scope reparenting, which turned
  "why does it hang" into "why do orphans accumulate", which is the real bug.
- 2026-07-14 — resolved, commit 0348fae0.
