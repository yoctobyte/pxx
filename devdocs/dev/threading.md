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

## Heap & shared state — the safety contract

The heap allocator is thread-safe **only under `--threadsafe`** (a `{$threadsafe
on}` directive too): an x86-64 lock-prefixed spinlock around `PXXAlloc`/`PXXFree`.
An `Execute` that allocates concurrently (managed strings, `GetMem`, objects)
**must** be compiled `--threadsafe`. Demonstrated by `test_thread_heap`: 4 threads ×
12k `GetMem`/`FreeMem` = 0 errors with the flag; **SIGSEGV every run without it**.

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
