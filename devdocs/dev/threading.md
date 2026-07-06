# Libc-free threading (PXX)

The multithreading subsystem ([[meta-multithreading]] epic). Real OS threads with
**zero libc** — pure Linux syscalls (`clone`/`futex`/`mmap`). x86-64 today; i386 and
cross are clean compile-errors until their backends land. Threading is **opt-in**:
nothing here is pulled unless a program `uses` a `pal*` unit, and the
single-threaded self-host build stays byte-identical.

Pin: landed at **v98**.

## The layers (bottom-up)

```
  user TThread / TMutex / TEvent / EnterCriticalSection / RunOnce
        |
  lib/rtl/palthreadobj.pas   TThread class (subclass + override Execute)
  lib/rtl/palsync.pas        TMutex, TEvent, TRTLCriticalSection, RunOnce
  lib/rtl/palthread.pas      PalThreadCreate/Join, PalFutex*, PalThreadSelf
        |
  compiler intrinsics        __pxxclone (trampoline)  +  __pxxatomic_xchg/cas/add
        |
  Linux syscalls             clone(2) / futex(2) / mmap(2)  via __pxxrawsyscall
```

Everything above the intrinsics is ordinary Pascal RTL. The compiler contributes
exactly two machine-code things: the clone trampoline and the atomic ops.

## Why `__pxxclone` is a hand-emitted stub, not `__pxxrawsyscall`

`clone(2)` is the one syscall that can't ride the generic `__pxxrawsyscall` path:
after the syscall the **child** resumes *inside the syscall wrapper* but on a brand
new stack, and would `ret` through a torn frame. The child must instead branch on
its zero return, fetch the entry pointer + argument the parent staged on the child
stack, `call` the Pascal entry, then `SYS_exit` — never returning to Pascal. That
branch is why it's a hand-emitted stub (pxx inline-asm has no branches yet).

Pipeline mirrors `__pxxcoswitch`: parser `AN_CLONE(72)` → `IR_CLONE(62)` → x86-64
codegen moves the 5 args (flags, childStack, entry, arg, ctidptr) into the SysV arg
regs and `call`s the stub (`compiler/thread_emit.inc`, `EnsureCloneStub`). The stub
is emitted **lazily with a jmp-over** the first time `IR_CLONE` is codegen'd, so it's
self-contained whether `__pxxclone` is used in the main program or a `uses`d unit
(an earlier pre-scan-flag attempt missed unit uses — units load after the up-front
runtime-stub region — and fell through into the stub).

Join is race-free via `CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID`: the kernel writes
the child tid into a futex word at clone time and clears it + futex-wakes on exit;
`PalThreadJoin` futex-waits on that word, then `munmap`s the stack.

## Atomics

`__pxxatomic_xchg(addr,val)` / `__pxxatomic_cas(addr,exp,new)` /
`__pxxatomic_add(addr,delta)` — one `AN_ATOMIC(73)`/`IR_ATOMIC(63)` node with the op
baked at parse time. x86-64 emits a 32-bit lock-prefixed rmw (`xchg` / `lock
cmpxchg` / `lock xadd`) returning the **old** value. These are the substrate for the
futex mutex (CAS fast path) and atomic counters.

## Sync primitives (`palsync`)

- **TMutex** — Drepper 3-state futex mutex (0 free / 1 locked / 2 contended).
  Uncontended lock+unlock is pure userspace (one CAS / one xchg, no syscall); only
  genuine contention enters the kernel.
- **TEvent** — manual-reset (level-triggered "go gun", wakes all) or auto-reset
  (one-waiter hand-off that CAS-consumes the signal).
- **TRTLCriticalSection** — `TMutex` under the FPC System names
  (`InitCriticalSection`/`EnterCriticalSection`/`LeaveCriticalSection`/…), so
  existing threaded Pascal compiles unchanged.
- **RunOnce** — `pthread_once` semantics; the initialiser runs exactly once across
  all racers.

## TThread (`palthreadobj`)

```pascal
type TWorker = class(TThread) protected procedure Execute; override; end;
w := TWorker.Create(True);  w.Start;  ...  w.WaitFor;
```

A file-level trampoline (`ThreadObjLauncher`) receives the instance from
`PalThreadCreate` and virtual-dispatches into the subclass `Execute`.

## Tid identity — who writes the tid, and when it is safe to read

There are two tid fields in `TThreadHandle`, with different write timing:

| field     | writer                | written when                          | valid until      |
|-----------|-----------------------|---------------------------------------|------------------|
| `TidWord` | **kernel** (`CLONE_PARENT_SETTID`) | before the child runs any user code | thread exit (`CLONE_CHILD_CLEARTID` zeroes it + futex-wakes join) |
| `Tid`     | **parent**, user space | after `__pxxclone` returns in the parent | handle lifetime |

The consequence is a startup race on `Tid`: the child can be scheduled and reach
`Execute` **before** the parent's `h.Tid := __pxxclone(...)` store lands. Any
*child-side* identity check against `Tid` (`CurrentThread`'s registry match,
`Suspend`'s own-thread guard, `WaitFor`/`Destroy` self-call guards) can then
compare against a stale `0`. Observed in practice: `test_tthread_final`'s
`CurrentThread = Self` failed ~1% of runs (the recurring `make stabilize`
flake), and a lost `Suspend` guard would skip the self-park entirely — leaving
`while not s.Suspended` in the caller spinning forever.

**The fix (2026-07-06, `86f16026`):** `ThreadObjLauncher` writes its own tid
(`PalThreadSelf`) into `FHandlePtr^.Tid` as its first act, before `Execute`.

- **Safe:** all child-side reads are now program-ordered after that store. The
  parent's later store writes the *identical value*, so the duplicate is benign
  — even on 32-bit targets where an Int64 store tears into two word stores,
  every interleaving of two same-value stores yields the same bytes.
- **Zero cost:** no locking, no handshake, no delay to thread start — one store
  the child performs anyway before touching anything tid-dependent.

**Rejected alternatives** (for the record, so nobody "improves" this later):

- *Startup handshake* (child spins/futex-waits until the parent has stored
  `Tid`): correct but strictly worse — adds synchronization and couples the
  child's start latency to the parent's scheduling. Nothing needs it.
- *`CLONE_CHILD_SETTID` pointed at `Tid`*: the kernel would write the tid in
  the child's context before it runs user code — equally race-free, equally
  zero-cost at runtime, and arguably the cleanest. Rejected on porting risk,
  not performance: it touches all five per-target `__pxxclone` stubs, and the
  kernel writes a 32-bit `pid_t` while `Tid` is `Int64` — exactly the
  width/endianness trap class of the v184 arm32 tid-high-word bug (a garbage
  high word surfaced far away as `pthread_join` ESRCH). If a third PAL consumer
  with child-side tid checks ever appears, promote the fix into the PAL this
  way; until then the one-line launcher store wins.

**Where the contract lives in code:** `TThreadHandle` in `lib/rtl/palthread.pas`
carries the RACE CONTRACT comment (parent-written `Tid` vs kernel-written
`TidWord`); the launcher self-write in `lib/rtl/palthreadobj.pas` explains the
consumer side. The C pthread shim (`lib/crtl/src/pthread.c`) is *not* affected:
its registry is populated under a lock before `pthread_create` returns, every
`pthread_join(t)` caller can only hold `t` after that return, and
`pthread_self` bypasses the registry (direct `gettid`) — no child-side read of
the parent-written field exists there.

## Heap & shared state — the safety contract

The heap allocator is thread-safe **only under `--threadsafe`** (a `{$threadsafe
on}` directive too): an x86-64 lock-prefixed spinlock around `PXXAlloc`/`PXXFree`.
An `Execute` that allocates concurrently (managed strings, `GetMem`, objects)
**must** be compiled `--threadsafe`. Demonstrated by `test_thread_heap`: 4 threads ×
12k `GetMem`/`FreeMem` = 0 errors with the flag; **SIGSEGV every run without it**.

### Heap contract by memory-management mode (feature-threadsafe-heap-contract)

There is ONE allocator (`compiler/builtin/builtinheap.pas`: free-list + bump
arena over `mmap`, or a fixed static arena on ESP) and every allocation family
routes through it — `GetMem`/`New`/`ReallocMem`, class `Create`, AnsiString,
dynamic arrays, managed-record helpers. So the per-mode contract is about how
that single allocator is *entered*:

| Mode | Allocator backing | Threads + concurrent alloc |
|---|---|---|
| hosted x86-64, `--threadsafe` | mmap arenas, **spinlock** (`BSS_HEAP_LOCK`, `EmitAcquireHeapLock` wraps every alloc/free/realloc codegen site) + lock-prefixed ARC refcounts + statement-atomic console I/O | **supported** — the only supported combination |
| hosted x86-64, default | same allocator, **no locking anywhere** | **rejected at compile time**: `__pxxclone` (under all of `PalThreadCreate`/`TThread`) errors without `--threadsafe` |
| hosted 32-bit (i386/arm32) & aarch64 cross | same allocator, no lock implementation | `--threadsafe` / `{$threadsafe on}` **rejected at compile time** (was silently accepted, emitting an unlocked binary); the clone stub is x86-64-only anyway |
| ESP static arena (xtensa / riscv32, bare) | single 64 KiB static arena, bump-only | single-threaded by contract; no `clone`/`futex` syscalls exist there, and `--threadsafe` is rejected like other cross targets. FreeRTOS tasks are outside the PXX runtime — allocating from more than one task is undefined |

Refcounting vs heap safety stay SEPARATE layers: the lock-prefixed ARC
refcount updates are necessary but not sufficient — concurrent
allocation/free needs the heap spinlock, which is why both hang off the same
`--threadsafe` mode rather than being independently selectable.

Validated by `test_thread_heap` (raw GetMem/FreeMem) and
`test_thread_heap_mixed` (concurrent AnsiString concat/SetLength, dynarray
SetLength/element writes, dynarray-of-AnsiString, class Create/Free,
GetMem/ReallocMem/FreeMem — 4 threads, tag-verified, 0 errors).

The single-threaded self-host took shortcuts that are *not* yet thread-safe — most
notably the per-process exception-chain head (`BSS_EXC_TOP`, shared by CoSwitch) and
other shared globals. Those are tracked under
[[audit-shared-global-reentrancy-thread-safety]] and need per-thread TLS (no
`CLONE_SETTLS` yet — child currently shares the parent fs base).

## Tests / gate

`make test-threads` (x86-64, in `make test`): `test_thread_clone`, `test_palthread`,
`test_atomic_counter`, `test_mutex`, `test_event`, `test_critsec_once`,
`test_tthread`, `test_thread_heap` (`--threadsafe`). tids stay out of stdout so
output is deterministic.

## What's done / what's next

Done (x86-64): M1 primitives, M2 atomics+mutex+event+critsec+once, M3 TThread,
M5 heap-safety *validated*. Remaining (each ticketed): i386 trampoline + atomics;
condition variable; `TThread.Synchronize`/Queue + virtual destructor/auto-join;
per-thread TLS; re-export `TThread` from `classes`; M5 heap *optimisation*
(per-thread arenas / lock-free fast path); M4 C `pthread` shim
([[feature-syscall-pthread-shim]]) reusing this PAL.
