# Concurrency & memory model

Design record for how PXX offers concurrency across its targets, and why the
choice is **target-appropriate** rather than one-size-fits-all. Decided
2026-06-18.

## Three tools, not three implementations of one feature

| Tool | What it is | Memory per unit | Targets | Home |
| --- | --- | --- | --- | --- |
| **Stackless coroutine** | body transformed into a state machine (step fn + heap instance holding resume point + persisted locals) | `sizeof(persisted locals)` — tens of bytes, no stack | **all** (no per-target asm) | embedded / ESP default |
| **Stackful coroutine** | body runs on its own heap stack, switched by a context-switch primitive | a whole stack, sized for the deepest suspended call chain — hundreds–thousands of bytes | x86-64 today (port pending) | hosted rich coroutines |
| **Thread** | preemptive OS/RTOS execution context | a full task/thread stack, reserved for the thread's lifetime | hosted = pthreads; ESP = FreeRTOS tasks | parallelism / multicore |

They **compose**: a single program may freely mix stackless and stackful
coroutines (backend is a per-routine compile-time choice; the for-in /
value+done iteration protocol is identical for both). Threads are a separate
axis — a thread may itself run coroutines.

## The memory math (why stackless is the embedded default)

- **Stackless instance** = only the locals that live across a suspension, in one
  heap struct. No call-frame storage. Tens of bytes.
- **Stackful instance** = an entire stack that must cover the deepest call chain
  while the coroutine is suspended. Typically **10–100×** the stackless size.
- The stackful stack lives on the **heap**, allocated when the coroutine starts
  and **freed when it completes** — so *sequential* coroutines reuse the memory;
  only *concurrently-suspended* ones each need their own live stack at once.

This is far cheaper than threads (on-demand, you-sized, lifetime-scoped, no guard
page, no OS bookkeeping), so the "hundreds of live coroutines" case is a
non-issue in practice — for scale, a stackless coroutine costs less than a
dictionary entry in MicroPython. **Hundreds of *stackful* coroutines already
signal a genuinely complex application**, and even then the budget is usually
fine. The reason stackless is still the embedded *default* is not feasibility —
it is that stackless is bounded and known at compile time, which is the right
posture on a part with **no MMU** (no guard page to catch a stack overflow; every
stack size is a static guess).

## Backend selection (planned: auto, target-aware)

Today bare `; generator;` / `; async;` always use the **stackful** backend, and
you force the other with an explicit `stackful;` / `stackless;` directive. The
planned auto rule:

1. **Eligible → stackless.** Eligible = structured suspension points only
   (`yield`/`await` at the top level or inside `for`/`while`/`if`, never in
   `case`/`repeat`/`with`/a condition/a `for` bound/`try`..`except`) **and** no
   managed local (string / dynamic array / record) live across a suspension.
2. **Ineligible →** use **stackful**, *but only on a target that has the stackful
   backend*. On a target without it (every 32-bit target today; ESP), it is a
   **hard error** naming the feature that forced it.
3. Once stackful is ported to a target, that hard error becomes a **cost
   warning**:
   ```
   warning: async Foo upscaled to stackful (managed local 's' lives across await)
            — costs a ~N-byte heap stack per live instance; ESP RAM is tight
   ```
   Naming the trigger + line + the per-instance stack cost is the whole point:
   the programmer keeps rich code with eyes open, or rewrites to stay stackless.

On a no-stackful target this is effectively **"stackless or a clear error"** —
the correct contract for a no-MMU part.

## `async` semantics recap

`async` is a **non-viral** marker (does not change the return type, does not
color callers). It legalises `await E` in the body. Under stackful, `async`/
`await` are *documentary* (`await E` == `E`; the coroutine runs to its next
suspension on the same heap stack). Under stackless, the body is split into a
state machine at each `await`. Per-`await` markers are what make the stackless
transform **local** — no whole-program analysis, works with separate compilation
and indirect calls. See [dialect/generators.md](../dialect/generators.md) and
[dialect/routines.md](../dialect/routines.md).

## Threads

- **Threads ⇒ FreeRTOS / pthreads — never a bare-metal scheduler.** PXX will not
  ship a hand-rolled bare scheduler: anyone who wants threads on ESP is, in
  practice, already pulling in ESP-IDF for Wi-Fi / BLE / drivers, so threads
  route through **FreeRTOS tasks** (the IDF profile). A bare program that asks
  for threads is a **hard error** pointing at `--esp-profile=idf`.
- Each FreeRTOS task is a **statically-sized stack** (no MMU growth) — same
  memory discipline as stackful coroutines, picked at task creation.
- **ESP32 is dual-core SMP** under FreeRTOS (PRO/APP). The "core 0 = networking,
  core 1 = app" split is an **IDF pinning *convention*, not hardware-enforced** —
  tasks can be pinned to a core or left floating. Expose this as a thin
  task-binding (create + optional core pin), **not** new language syntax.
- `--threadsafe` / `{$THREADSAFE ON}` already emits atomic refcounts for managed
  values — the shared-runtime safety groundwork is in place. The language surface
  for spawn/join/locks/`parallel for` is tracked in
  [feature-parallel-processing](../progress/backlog/feature-parallel-processing.md).

## ESP target profiles

Two **first-class** profiles, both supported, chosen by `--esp-profile=`:

- **`idf`** — ESP-IDF + FreeRTOS + vendor libraries. The default (≈99% of real
  apps use *something* from IDF). Required for threads and any IDF feature.
- **`bare`** — self-contained image, own startup, UART MMIO, no IDF (see
  [esp32-support.md](esp32-support.md) § Bare-metal boot). One-flag opt-in. Kept
  first-class because it is genuinely useful: tiny images, no heavy toolchain,
  and **much faster / simpler for language tests** (boot a raw ELF under qemu,
  diff UART vs the x86-64 oracle — no IDF project, no flash image).

Hard rule: **bare stays self-contained.** FreeRTOS must never become a hidden
runtime dependency of the bare profile — that self-containment is its entire
reason to exist.
