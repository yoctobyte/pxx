---
prio: 70
track: B
---

> **Track corrected P -> B** by frank-optimize, 2026-08-29. Nothing here is the Pascal frontend; the failing assertion is about output from `lib/rtl/scheduler.pas`'s fatal arm, so it is B's file. See the enrichment at the bottom before working it.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_sched_reactor_exhaustion.pas red at dd9450b0ce75 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T19:06:20Z
- **Test source:** test/test_sched_reactor_exhaustion.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_sched_reactor_exhaustion.pas'` at dd9450b0ce751cae3ad319dc7e2b51dd016ea471

## Range
> **The named sha `dd9450b0ce75` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `dd9450b0ce75`, last good `d47454937cd4`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
-fatal: scheduler out of reactor slots (MAX_REACTORS)
(tail)
ok: /tmp/testmgr-scratch-1186231/test_sched_exhaust26  [code=130456B  data=3976B  bss=47348B  procs=298]
expect_same: MISMATCH [test_sched_exhaust26-msg]
--- expected
+++ actual
@@ -1 +1 @@
-fatal: scheduler out of reactor slots (MAX_REACTORS)
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-29 — auto-closed by the seven watcher: `test-threads#src:test/test_sched_reactor_exhaustion.pas` passes at e54cc15a5c4e (tier native); it was red at dd9450b0ce75. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
- 2026-08-29 — **that auto-close is the third state change on this job, not a fix.**
  It went red, was closed "green again" (`3ebb2505c`), went red again as this
  ticket, and has now been closed "green again" a second time. A job that closes
  itself green on a schedule is describing a FLAKY ASSERTION, and the enrichment
  below says which assertion and why it is flaky. The watcher is right that the
  job passes; it cannot see that passing is not the same as fixed. Left in
  `done/` because that is the watcher's call to make about its own job, with the
  analysis kept so the third red is not triaged from scratch.

---

## Enriched 2026-08-29 by `frank-optimize` — the assertion that failed was the MESSAGE, not the status

Read the log tail closely: there is no `-rc` mismatch. The process **exited 216
correctly**. What failed is `test_sched_exhaust26-msg`, and the actual value is
**empty** — the fatal line never reached the log.

That is a different defect from
[[bug-b-concurrent-halt-from-several-threads-exits-0]] (the exit-status one,
fixed the same day), and fixing that one does **not** fix this one. Worth saying
plainly, because the two live in the same six lines of `scheduler.pas` and the
timing invites the assumption.

### The mechanism, by inspection

```pascal
    ignore := __pxxatomic_xchg(@regLock, 0);
    if __pxxatomic_cas(@fatalOnce, 0, 1) = 0 then
      writeln('fatal: scheduler out of reactor slots (MAX_REACTORS)');
    Halt(216);
```

`fatalOnce` guarantees exactly one thread *prints*. It orders nothing else.
Every **other** refused thread falls straight through to `Halt(216)`, and
`Halt` is `exit_group` — it takes the whole process down, including the thread
that is part-way through `writeln`. So the reporting thread is racing every
other refused thread, and losing that race truncates or erases the line while
the exit status stays perfectly correct.

**This race is present in both versions of the arm** — it was there while the
arm called `exit_group` through `__pxxrawsyscall` (2026-08-28 to 2026-08-29),
and it is there now that the workaround is reverted to `Halt(216)`. The revert
neither caused nor fixed it. `fatalOnce` was always a print-once guard, never a
print-completely guard.

### Not reproduced here, and that is a fact about this box

- reverted source (`Halt`), HEAD compiler: **0/100** non-216, **0/100** empty
- workaround source (raw `exit_group`), HEAD compiler: **0/20** empty

So the mechanism above is **a hypothesis supported by reading the code, not by a
local reproduction.** It fires on `seven` and not here, which is what a
narrow timing window on a differently-loaded box looks like — and is consistent
with the earlier instance of this same job going red, then green, then red again
(`3ebb2505c` closed the first as "job green again"). **A test that closes itself
as green is the signature of a flaky assertion, not of a fix.**

### Why the test is flaky by construction

The suite asserts on a line printed by one thread while other threads are
concurrently killing the process. Nothing orders those. The assertion can only
be as deterministic as that ordering, and there is no ordering.

Options for whoever takes it, cheapest first:

1. **Make the reporter the killer.** The thread that wins `fatalOnce` prints and
   then halts; every loser parks *without* halting. The earlier investigation
   found parking deadlocks against `Halt`'s thread-join — but that finding
   predates the `exit_group` fix, and `exit_group` does not wait for anything, so
   it deserves re-measuring rather than inheriting.
2. **Flush before the others can win**, if the runtime has a flush the fatal path
   can call. Narrows the window; does not close it.
3. **Assert only on the exit status** and drop the message assertion. Honest, and
   loses the check that the fatal is *named* — which is what makes the guard
   useful to a human reading a CI log.

Option 1 is the only one that removes the race rather than shrinking it.

### Same shape as the ticket it sits next to

The exit-status bug was found because a fatal reported SUCCESS. This one is a
fatal reporting *silence*. Both are the failure's REPORT being lost rather than
the failure itself — the third instance of that shape in this area, after the
i386 `exit_group` number in `pxxcio.pas` that made every failing C program exit
0. When a guard fires, the thing most likely to go missing is the evidence that
it fired.
