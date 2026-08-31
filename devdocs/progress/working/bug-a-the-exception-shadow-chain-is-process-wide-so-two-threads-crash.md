---
slug: bug-a-the-exception-shadow-chain-is-process-wide-so-two-threads-crash
track: A
prio: 70
type: bug
status: working
owner: frankS
blocked-by: []
summary: "MEASURED: 18 of 22 two-threaded runs CRASH -- mostly SIGSEGV (139), sometimes exit 217 with an exception that escaped its own `try`. The single-threaded control is clean in 12 of 12 runs of the SAME BINARY, in the same process, moments earlier. `BSS_EXC_TOP` is the setjmp shadow-chain HEAD and is one process-wide slot, so two threads push and pop try-frames onto one chain and a raise longjmps into the other thread's dead frame. This is worse than the signal-slot race fixed in 47439504c: that produced wrong VALUES, this terminates the process. Allocation-free repro, so it is not the heap lock. Scope is large -- ~64 references to BSS_EXC_TOP across 14 files including all seven backends and coroutine_emit.inc -- so it is filed with the diagnosis banked, not microfixed."
---

# The exception shadow chain is process-wide, so two threads crash

- **Found:** 2026-08-31 by frankA, at frankS's suggestion after they fixed the
  signal-field twin ([[bug-a-the-parked-signal-slots-are-process-wide-and-race-across-threads]],
  `47439504c`). They deliberately did not assert it from the shape; this is the
  repro they asked for.

## Measured

Two threads, each running an identical loop of `try raise 7 except ... end`,
100000 iterations. **Allocation-free on purpose**: an exception carrying an
object would take the heap lock on every raise, serialising the threads and
hiding the interleaving under test.

```
phase 1, single-threaded (same binary, same process, seconds earlier):
  hitsA=100000  wrongA=0  escaped=0        clean in 12 of 12 runs

phase 2, two threads:
  18 of 22 runs FAIL
    rc=139  SIGSEGV                         (dominant)
    rc=217  "Unhandled exception"           an exception escaped its own try
```

The built-in control is the point: **the failure needs only the second thread.**
Nothing else about the run changes.

It is a race, not a deterministic break — N=100 and N=10000 have both passed,
N=1000 has failed. Do not read a single green run as a fix.

## Why

`EnableExceptionRuntime` (`pasparser_proc.inc:3003`) allocates four
**process-wide** slots:

```pascal
BSS_EXC_TOP := BSSSize; ...   { the setjmp shadow-chain HEAD }
BSS_EXC_OBJ := ...            { the exception object }
BSS_EXC_CLS := ...
BSS_EXC_ADDR := ...           { the raise site }
```

`BSS_EXC_TOP` is not a status value like the signal fields — it is the **head of
the chain the unwinder walks**. Every `try` pushes a setjmp buffer onto it and
every exit pops it. Two threads share one head, so thread A's `try` links onto
thread B's frame, and a raise longjmps into a frame that belongs to the other
thread and may already be dead. That is why this crashes rather than merely
answering wrong.

(The allocation itself is fine and is NOT the `BSS_IO_OWNER` bug: it is
demand-driven and idempotent through `ExceptionUsed`, so every frontend reaches
it. Checked before filing.)

## Why it is filed and not fixed

The signal fix moved **four** fields with four writers. This is:

| | refs |
| --- | --- |
| `BSS_EXC_TOP` | ~64, across 14 files — all seven backends, plus `coroutine_emit.inc` (20) |
| `BSS_EXC_OBJ` / `_ADDR` | ~41 more |

`coroutine_emit.inc` is the part that makes this a design question rather than a
port of `47439504c`: a coroutine **switches stacks**, so "the current thread's
chain" and "the current coroutine's chain" are not the same question, and
per-thread storage may be the wrong axis for it. Answer that before writing code.

And TLS is x86-64-only (`EmitTlsMainInstall`), so the fix helps one target and
the other four keep the bug — the same honest limit frankS recorded.

## Note

`--threadsafe` + exceptions is **not** documented as unsupported anywhere, and
nothing refuses it. Until this is fixed, a `--threadsafe` program that raises on
more than one thread is unsound; a refusal, or a documented limit, may be worth
more than nothing while the real fix waits.

Repro kept at `$SCRATCH/excrace.pas` (frankA's session); it is 50 lines and
trivially rebuilt from the description above.
