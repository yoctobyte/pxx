# Async, coroutines, and `yield`

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-unified-heap-allocator
- **Opened:** 2026-06-06 (from rainy-afternoon / plan-async-coroutines.md)

## Motivation

A shared-language arc: a resumable-execution mechanism plus an event loop, usable
from Pascal, Nil Python, and future frontends. Cooperative concurrency is also
arguably the right model for ESP32 (predictable, low-RAM, no preemption).

## Approach — PIVOTED to stackful coroutines (2026-06-16)

The original plan (`developer/plan-async-coroutines.md`) was a compiler
**state-machine / resumable-frame transform** (stackless, C#/Python `async`
style). That is a brutal CPS transform on a stack-machine codegen with no SSA,
plus viral function coloring and yield-location restrictions. **Defer it.**

Instead: **stackful coroutines (fibers / green threads).** A coroutine = its own
heap stack + a saved register context; switching is a tiny per-target asm routine.

- ~90% is a **library** (PXX-only — full feature set; see
  feature-fpc-vs-pxx-feature-boundary). Scheduler, coroutine type, channels, event
  loop: all Pascal.
- Only `CoSwitch` needs asm — ~15 instructions × 6 targets (save callee-saved
  regs + sp, restore, ret). The codegen already has inline asm + per-target
  encoders.
- **No coloring, no transform** — works with existing blocking code, loops,
  `try`. Cooperative yields avoid preemption races.
- **Start with generators** (feature-generators-yield) as the on-ramp: same
  `CoSwitch`, simpler consumer-driven protocol, immediately useful.

### Layers (build order)

1. `CoSwitch` (asm) + `TCoroutine` (heap stack). Save/restore `BSS_EXC_TOP` per
   coroutine (the setjmp exception chain is per-stack — must swap on switch, or a
   cross-coroutine `raise` unwinds the wrong frames).
2. Cooperative scheduler: ready queue, `Spawn`/`Yield`/`RunUntilDone`. Single OS
   thread first (cooperative within one thread is race-free); M:N is much later.
3. Channels / mailboxes (optional).
4. **Async-I/O reactor:** a "blocking" recv registers its fd and `Yield`s; the
   scheduler's `select`/`poll`/`epoll` wakes it — makes Synapse-style code async
   transparently. The payoff.
5. ESP32 reactor (UART / sockets).
6. (Optional, later) `async`/`await` sugar over `Spawn`/`Yield`; stackless
   transform only for the RAM-critical embedded hot path.

### Gotchas specific to PXX

- Exception-frame swap on context switch (above) — easy to miss, corrupts on the
  first cross-coroutine `raise`.
- `--threadsafe`: single-thread scheduler first; coroutines across real threads
  (M:N) is a separate, later add.
- gdb backtraces break across stack switches (the prologue-scan recipe still
  works).
- Stack size is the footgun: fixed/configurable, guard page (hosted) / canary
  (embedded).

**Sequencing:** allocator groundwork first (many small coroutine stacks →
feature-unified-heap-allocator). Generators (feature-generators-yield) lead.

## Acceptance

A coroutine/`yield` test suspends and resumes correctly on the stackful mechanism;
the async-I/O reactor drives a Synapse socket without blocking the scheduler;
self-host fixedpoint + cross-bootstrap unaffected (library-only).

## Log
- 2026-06-06 — ticket opened from rainy-afternoon.md.
- 2026-06-16 — pivoted from stackless state-machine transform to stackful
  coroutines (library + 6 asm `CoSwitch` stubs); generators (feature-
  generators-yield) split out as the on-ramp; stackless deferred to an embedded
  optimization.
