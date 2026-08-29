---
summary: "Halt(errcode) from several parallel-for workers at once sometimes exits 0 instead of the code: same binary and width give 0, 216, 0 across runs. A fatal that reports SUCCESS to its caller. Six plain palthread threads all calling Halt do NOT reproduce it, so the cause is not concurrency alone and is not isolated. Reproduced, not diagnosed."
track: B
prio: 55
type: bug
status: backlog
owner: unassigned
blocked-by: []
---

# `Halt` from several parallel-for workers at once can exit 0

Found while building the reactor-exhaustion guard in
[[bug-a-the-17th-thread-silently-aliases-reactor-slot-0]]. The guard needed to
die loudly; `Halt(216)` was the obvious body, mirroring `SpawnSized`'s `MAX_CO`
arm forty lines below it. It turned out not to be reliable, so that arm ships
calling `exit_group` directly and this ticket records what was left behind.

## Observed

`lib/rtl/scheduler.pas`'s exhaustion arm, built `-dPXX_SCHED_TINY_REACTORS`
(`MAX_REACTORS` = 2) so N parallel-for workers are refused a reactor. Each
refused worker printed one line and called `Halt(216)`. Same binary, same
width, repeated:

| workers | exit statuses |
| ---: | --- |
| 3 | 216 216 216 |
| 4 | **0 216 0** |
| 8 | **0 0 0** |
| 20 | 216 216 216 |

Replacing the body with `exit_group(216)` gives **216 in 30/30** runs across 3,
4, 8, 20 and 64 workers, which is what shipped.

**Why this matters beyond the one arm:** a fatal whose exit status is sometimes
0 reports SUCCESS to whatever ran it. Every harness here reads exit status.

## What is NOT the cause — the obvious repro does not reproduce

Six plain `palthread` threads, each calling `Halt(216)` immediately, with no
parallel-for anywhere:

```pascal
uses palthread;
procedure Body(arg: Pointer); begin Halt(216); end;
{ 6 x PalThreadCreate(Body) then PalThreadJoin }
```

**Exit 216 in 6/6 runs** — and `main reached the end` printed each time, so the
recorded status survives main's normal completion. So it is not "concurrent
`Halt` races": something about halting from inside a **parallel-for worker**,
during **reactor attachment** (i.e. very early in the worker's life, when all
workers are tightly synchronised at startup), is involved.

That is as far as it was taken. Reproduced, bounded, **not diagnosed** — the
lane may well be A (the `Halt` site is compiler-emitted: a call to
`__pxx_run_finalizers` and then the epilogue's exit, see `EmitProgramEpilogue`)
rather than B. Filed under B because the reproduction lives in `lib/rtl` and B
found it; **re-file to A without ceremony if the epilogue turns out to own it.**

## Two related facts worth having before starting

- **`Halt`'s exit path joins the worker threads.** Two attempts to serialise the
  fatal so only one thread called `Halt` both HUNG (exit 124 under `timeout`, at
  4, 8 and 20 workers): holding the attach spinlock across the fatal, and
  releasing it but parking the losing threads. A parked thread is one the join
  waits on forever. Whatever the fix, it has to survive that.
- **`SpawnSized`'s `MAX_CO` guard is the same shape and still uses `Halt`.** It
  was measured at two concurrently-refused workers and exited 216, so it is not
  observed broken — but nothing makes it structurally safer, and it is the
  natural second instance to check once the mechanism is known.

## Method note

The first pass at this table sampled each width **once**, produced 216 / 0 / 0,
and got written up as a deterministic rule — "one refusal reports correctly, two
or more exit 0" — which is wrong, and had already reached a source comment
before re-running destroyed it. One sample per cell reads exactly like a
measurement. Repeat every cell of a race's table before drawing a conclusion
from its shape.
