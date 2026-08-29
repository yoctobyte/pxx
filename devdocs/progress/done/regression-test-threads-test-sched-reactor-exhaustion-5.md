---
prio: 70
track: B
owner: frank-b
status: done
---

> Track corrected P -> B: the test source is a Track B test and the subject is
> `lib/rtl/scheduler.pas`, a Track B file. The guess read the `.pas` extension
> as "Pascal frontend"; P is the frontend that *compiles* Pascal, not every
> test written in it. Nothing in the compiler is implicated — the same source
> is red or green depending only on thread timing.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_sched_reactor_exhaustion.pas red at c687ffeecb1f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T20:03:52Z
- **Test source:** test/test_sched_reactor_exhaustion.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_sched_reactor_exhaustion.pas'` at c687ffeecb1f60010c98799c26f5b2a2bb5b5a50

## Range
> **The named sha `c687ffeecb1f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c687ffeecb1f`, last good `d1b84e6c9604`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
-fatal: scheduler out of reactor slots (MAX_REACTORS)
(tail)
ok: /tmp/testmgr-scratch-1499318/test_sched_exhaust26  [code=130125B  data=3976B  bss=47348B  procs=298]
expect_same: MISMATCH [test_sched_exhaust26-msg]
--- expected
+++ actual
@@ -1 +1 @@
-fatal: scheduler out of reactor slots (MAX_REACTORS)
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (frank-b, 2026-08-29) — CONFIRMED, cause found, fixed

Mine, and a real defect in the fix I landed as `9bd3da8b2`, not a flake.

**Cause.** Every refused thread calls `Halt(216)`; exactly one of them first
wins a CAS and prints the fatal. `Halt` is `exit_group` (since the compiler fix
in `bug-b-concurrent-halt-from-several-threads-exits-0`), so a *losing* thread
reaching `Halt` ends every thread — including the winner, mid-`writeln`. The
window is CAS-win → `write` syscall. When a loser wins that race the process
still exits 216 with an empty log: **a fatal that reports its number and not its
reason.** That is exactly the observed evidence — the `-rc` assertion passed and
only `-msg` mismatched.

**Reproduced locally**, so this is not host-specific — it is timing-thin, and
`seven` is simply wider:

| shape | empty message |
| --- | --- |
| 4 workers, output to a file | 0 / 40 |
| 24 workers, output to a **pipe** | 0 / 12 |
| 24 workers, output to a **file** | **5 / 40** |

The pipe row is why my first local check said "cannot reproduce" and the harness
disagreed: I probed a shape the harness does not use. The recipe redirects to a
file. *A refutation is scoped to the shape that was tested* — and I tested the
wrong one first.

**Fix.** The winner sets `fatalDone` after writing; a loser waits on it before
calling `Halt`. Bounded (`FATAL_SPIN_MAX`), because a winner that never arrives
must degrade to a late fatal, never to a hang — a hang is the one outcome worse
than a quiet exit here.

**After:** 40/40 correct at 24 workers (the width that reproduced 5/40 before),
40/40 on the real test, `test_sched_reactors_wide` and
`test_async_parallel_compat` 5/5 each, self-host fixedpoint converged in 2
rounds.

**Not claimed:** I did not reproduce the *original* 4-worker-on-24-core
condition `seven` hit; I reproduced the mechanism by widening it on a 12-core
box. The fix removes the race by construction, so both are covered, but the
`seven`-shaped run is verified by Track T's next sweep, not by me.
- 2026-08-29 — resolved, commit 8f0e1a589.

## Log
- 2026-08-29 — auto-closed by the seven watcher: `test-threads#src:test/test_sched_reactor_exhaustion.pas` passes at 9beb2af4946c (tier native); it was red at c687ffeecb1f. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
- 2026-08-29 (frank-b) — **that auto-close was not evidence, and it landed on a
  real bug.** The failure is intermittent by construction: a lost race between a
  losing thread's `exit_group` and the winner's `write`, measured here at 5 runs
  in 40 at 24 workers and 0 in 40 at 4. A single green run of an intermittent
  test is the expected outcome ~90% of the time even with the defect fully
  present, so it cannot distinguish "fixed" from "did not lose the race this
  time". Both sides of this file were kept for that reason: the watcher's green
  is a true observation and a false conclusion.
  Generalises past this ticket: *auto-close on one pass is sound for a
  deterministic test and unsound for a racy one*, and nothing in the stub tells
  the closer which it is holding. Worth a Track T look at whether NEW-GREEN
  should require N passes when the prior red was a mismatch on a
  concurrency-tagged job — I have not filed that, because whether it is worth
  the sweep time is T's call, not mine.
