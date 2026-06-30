# Syscall-only pthread shim for libc-free C libraries

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-threadsafe-heap-contract, feature-threadsafe-io-serialization
- **Unblocks:** task-sqlite-libc-free-runtime-bringup
- **Found / Opened:** 2026-06-28, Track B sqlite/pthread discussion

## Motivation

Some C libraries, SQLite included when built with `SQLITE_THREADSAFE=1` or `2`,
expect a pthread surface. The current PXX path can parse/import `<pthread.h>`,
and Pascal thread tests can call the host `libpthread.so.0`, but libc-free C
library bring-up should not need glibc's pthread implementation.

The goal is a constrained, PXX-owned, source-level pthread subset implemented
with Linux syscalls. This is not a full glibc `libpthread` ABI clone.

For SQLite bring-up, keep the default path on `SQLITE_THREADSAFE=0` until the
current schema-parse corruption is fixed. This ticket is the later multithreaded
SQLite path.

## Scope

Initial Linux/x86-64 shim in `lib/crtl`:

- provide `lib/crtl/src/pthread.c` and keep `lib/crtl/include/pthread.h`
  compatible with the exposed subset;
- implement `pthread_mutex_*` with atomics plus `SYS_futex`;
- implement `pthread_once` with atomic state plus `SYS_futex`;
- implement `pthread_cond_*` with a futex sequence counter;
- provide `pthread_self` / `pthread_equal`;
- add `pthread_key_*` only if SQLite or another concrete target hits TLS paths;
- defer `pthread_create` / `pthread_join` until a target needs worker threads.

If/when thread creation is added, use `clone`/`clone3` directly with a PXX-owned
stack, child-tid futex join, and a small start trampoline. Keep cancellation,
robust mutexes, scheduler attributes, signal details, and full glibc TLS
semantics out of the first slice.

## Acceptance

- A libc-free C test unity-includes the shim and passes mutex contention,
  `pthread_once`, and producer/consumer condition-variable checks without any
  `DT_NEEDED` on `libpthread` or `libc`.
- Existing external `pthread` import behavior remains available when
  `--system-libs=pthread` is selected.
- SQLite built with `SQLITE_THREADSAFE=1` or `2` can initialize, open
  `:memory:`, execute a trivial schema statement, and close using the shim.
- Non-threadsafe SQLite (`SQLITE_THREADSAFE=0`) remains the recommended bring-up
  mode until the existing SQLite SQL execution bug is closed.

## Risks / constraints

- Real preemptive threads require the rest of the runtime to be honest. PXX has
  some threadsafe refcounting already, but heap safety is a separate Track A
  contract and may depend on memory-management mode; see
  [[feature-threadsafe-heap-contract]].
- Current `--threadsafe` support is primarily x86-64; i386 and other targets
  need separate work before this can be generalized.
- ESP-IDF should use the platform's FreeRTOS/pthread-like layer instead of this
  Linux syscall shim.

## Log

- 2026-06-28 — opened from Track B sqlite discussion. Decision: possible as a
  constrained syscall-only pthread subset, but keep immediate SQLite work on
  `SQLITE_THREADSAFE=0` and do not attempt a full glibc pthread clone.

## Part of the multithreading epic (2026-06-30)

Umbrella: [[meta-multithreading]]. Invariant: threading is opt-in/off-by-default;
single-threaded self-build stays byte-identical; no libc (Linux syscalls only).

## READY TO PICK — the libc-free PAL now exists (2026-06-30, Track A landed M1/M2)

The hard parts this ticket described as future work are **already built and tested**
on x86-64 — the C pthread shim should *reuse* them, not reinvent. See
`devdocs/dev/threading.md`. Concrete mapping:

| pthread surface            | reuse from the PXX PAL                                   |
|----------------------------|----------------------------------------------------------|
| `pthread_mutex_lock/unlock`| `lib/rtl/palsync.pas` TMutex — Drepper 3-state futex; port the *same* algorithm to `lib/crtl/src/pthread.c` (CAS fast path + `SYS_futex`). |
| `pthread_once`             | palsync `RunOnce` — CAS(0->1) winner + futex-wait losers. |
| `pthread_cond_*`           | futex sequence counter (palsync has no cond var yet — this shim and the Pascal side can share the design; file it once). |
| `pthread_self`/`equal`     | `gettid` (palthread `PalThreadSelf`).                     |
| `pthread_create`/`join`    | the `__pxxclone` trampoline already does clone(2)+stack+CHILD_CLEARTID join. From C, either expose a tiny intrinsic-backed helper or reimplement the same clone+trampoline in `pthread.c`. palthread `PalThreadCreate/Join` is the reference. |

Atomics: the compiler now has `__pxxatomic_xchg/cas/add` intrinsics — usable from
C lowering if the shim wants them instead of inline asm.

Heap-safety dependency is **de-risked**: the heap is validated thread-safe under
`--threadsafe` (test_thread_heap: 0 errors with the flag, SIGSEGV without). So a
threadsafe-SQLite path compiles `--threadsafe` and the contract holds on x86-64.
[[feature-threadsafe-heap-contract]] is still the formal contract doc, but the
runtime guarantee exists.

Still Track B (owns `lib/crtl/**`). First slice unchanged: mutex + once +
self/equal, libc-free, no `DT_NEEDED` on libpthread. cond var + create/join follow.
x86-64 first (the atomics/clone intrinsics are x86-64 today).
