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
- 2026-06-16 — **spawn/entry ABI decided: real procedural types instead of an
  asm entry shim.** The original DESIGN NOTE (PXX can't call a proc-var with
  args) was true, so the plan was a per-target shim that moves an rbx-slot arg
  into the ABI register. Instead implemented **procedural types** (standard
  Pascal, reusable) so a library `CoStart` can call `entry(arg)` directly — no
  shim, no rbx handoff, no compiler-emitted entry glue. CoStart will read the
  starting coroutine from a global (set by the scheduler before the first
  switch-in) and call `entry(arg)`; the initial frame's return address is just
  `@CoStart`.
  - **Phase A DONE (commits 59e1f4d + 8fe957e):** `type T = procedure(...)` /
    `function(...): R`, proc-typed var/param/global/local, `@Proc`/`nil` assign,
    `v(args)` indirect call (statement + expression) on **all 4 Linux targets**
    (x86-64/i386/aarch64/arm32), byte-identical, `test/test_proctype.pas` in
    test-core + test-i386. AN_CALL_IND/IR_CALL_IND; signature stored as a
    body-less Procs[] entry referenced by AliasProcSig/SymProcSig parallel
    arrays (TSymbol-field landmine). **Side-fix:** `@proc` (IR_PROCADDR) was
    x86-64-only; now implemented on i386/aarch64/arm32 (+ writeELF32 32-bit
    ProcAddrFix). `of object` method pointers (2-word) parsed-but-ignored —
    Phase B. >6/>8/>4 params per target not yet supported (async needs 1).
  - **Phase B DONE (x86-64):** `procedure(...) of object` / `function(...): R
    of object` method pointers. A method-pointer value is a 16-byte
    Code@0/Data@8 record (lazily-minted `MethodPtrRecId`); `m := @obj.Method`
    reuses the existing AN_METHODREF 2-word store; `m(args)` injects Self (Data)
    as arg0 and calls Code (IR_CALL_IND with IRC = extra-Self count). The cross
    backends' IR_CALL_IND method path is in place (guards count Self), but
    **method pointers are x86-64-only because class instances are x86-64-only**
    on this compiler ("class instantiation not yet supported" on i386/aarch64/
    arm32) — latent-correct for when classes land cross. `test/test_methcall.pas`
    in test-core. Note: bare `p;` (no-paren proc-var call) not supported; use
    `p()`.
  - **Still TODO:** Phase C — port CoSwitch to i386/aarch64/arm32, the library
    `CoStart` trampoline (calls `entry(arg)` via the proc-var call), and the
    cooperative scheduler (Spawn/Yield/RunUntilDone).
