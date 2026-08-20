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
  lib/rtl/palthread.pas      PalThreadCreate/Join, PalThreadSelf   [--threadsafe]
  lib/rtl/palfutex.pas       PalFutexWait/Wake/WaitTimeout         (no deps)
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

## Why `palfutex` is its own unit

Waiting on a word and *creating a thread* are different privileges. `PalFutex*`
used to live in `palthread`, and reaching that unit at all fails to compile
without `--threadsafe` (it holds `__pxxclone`, and the default heap/ARC/console
runtime is not thread-safe). That gate is right for thread creation and wrong for
a futex wait, which needs no thread-safe heap and no threads to compile.

The cost was structural rather than cosmetic: `syncobjs.TCriticalSection` had to
be a **spinlock**, because `uses syncobjs` must not start demanding
`--threadsafe` — Synapse's `ssfpc.inc` is exactly the caller that would break,
and it does no threading. `palatomic` is a separate unit for the same reason.

So the three syscall wrappers live in a dependency-free `palfutex`, `palsync`
uses that instead of `palthread`, and `TCriticalSection` is a real blocking
mutex. Measured on the thread-critical-section shape (three waiters blocked
0.6 s): 1.73 s of user CPU burnt spinning before, 0.00 s after, same wall clock
and the same 8000 answer. `uses` is not transitive, so every `PalFutex*` caller
carries its own `uses palfutex` — `palthread` re-exports nothing.

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
[[audit-shared-global-reentrancy-thread-safety]] and need per-thread TLS — which
now exists, as the section below.

## Thread-local storage (x86-64)

`PXX_CLONE_THREAD` does **not** set `CLONE_SETTLS`, so a fresh thread inherits
the parent's `fs` base and an `fs:`-relative slot silently aliases the parent's.
Measured, not assumed: strip the per-thread install out of `test_tls_base` and
four threads report ~39000 tag mismatches against each other.

The fix does **not** go through `clone`. `arch_prctl(ARCH_SET_FS)` acts on the
*calling* thread, so a thread installs its own block as its first act:

```pascal
b^ := Int64(PtrUInt(b));   { slot 0 = the block's own address }
__pxxrawsyscall(158 { arch_prctl }, $1002 { ARCH_SET_FS }, Int64(PtrUInt(b)), 0, 0, 0, 0);
```

That needs no compiler support at all — it is an ordinary syscall. Only the
**read** side does, because the x86-64 `fs` base is not readable as a register
(`rdfsbase` needs `CR4.FSGSBASE`, which is not guaranteed):

```pascal
p := __pxxTlsBase;                        { one instruction: mov rax, fs:[0] }
slot := PInt64(PtrUInt(p) + PtrUInt(n * 8));
```

**Slot 0 holds the block's own address.** That is the whole convention, and it is
what glibc and musl do for the same reason. `__pxxTlsBase` is deliberately
read-only and base-only: with the self-pointer in place, ordinary pointer
arithmetic reaches every future per-thread field — arena, errno, exception
stack, RNG — so no intrinsic-per-field is ever needed.

**Installing is mandatory and belongs in the launcher, before user code runs.**
A thread that skips it does not get a null base to check against; it gets the
*parent's* block, which is the aliasing failure above wearing a working-looking
pointer.

So the launcher does it, and the launcher is the **clone stub** — not the RTL.
On the child path, before anything Pascal runs, `EnsureCloneStub` carves
`TLS_BLOCK_SIZE` (128) bytes off the top of the child's stack, zeroes them,
writes the self-pointer and `arch_prctl`s the block:

```
childStack ─┐
            │  [ 128-byte TLS block: slot0 = self, slots 1..15 zeroed ]
            │  [ entry ][ arg ]        <- staged by the parent
   child rsp ┘  (grows down from here)
```

Putting it in the stub rather than in `palthreadobj` is what makes forgetting
unreachable: **every** pxx thread passes through `__pxxclone`, whatever frontend
or library created it. The cost is that `__pxxclone` now requires 144 usable
bytes of stack from its caller, which is documented at the intrinsic and is
nothing against `PAL_DEFAULT_STACK`. The block is zeroed rather than trusted —
`palthread` hands over fresh anonymous `mmap`, but `__pxxclone` is reachable
directly, and a reused stack would otherwise present the previous thread's slots
as this one's.

**The MAIN thread is the exception and is not covered yet**: it passes through no
stub, and a static pxx binary starts with `fs` base 0, so `__pxxTlsBase` faults
there unless the program installs a block itself. Tracked as
[[feature-a-tls-block-for-the-main-thread]] — it needs a shared startup emitter,
which does not exist today.

x86-64 only. The other targets have a readable thread register (aarch64
`tpidr_el0`, arm32 `tpidruro`, i386 `gs`) but no path this runtime uses to
*set* one — i386 in particular wants a `struct user_desc`, not a raw base — so
`__pxxTlsBase` errors there at compile time rather than returning a plausible
wrong pointer.

The consumer work — the per-thread allocator magazine that motivated this — is
[[feature-threadsafe-heap-optimize]], and it needs the main-thread block first.
A free win waits alongside it: the `--threadsafe` I/O lock does a `gettid`
**syscall per I/O statement** (`EmitIoLockStubs`), which a TLS slot turns into a
load.

## Tests / gate

`make test-threads` (x86-64, in `make test`): `test_thread_clone`, `test_palthread`,
`test_atomic_counter`, `test_mutex`, `test_event`, `test_critsec_once`,
`test_tthread`, `test_thread_heap`, `test_tls_base` (`--threadsafe`). tids stay
out of stdout so output is deterministic.

## What's done / what's next

Done (x86-64): M1 primitives, M2 atomics+mutex+event+critsec+once, M3 TThread,
M5 heap-safety *validated*. Remaining (each ticketed): i386 trampoline + atomics;
condition variable; `TThread.Synchronize`/Queue + virtual destructor/auto-join;
per-thread TLS *primitive* (`__pxxTlsBase`, x86-64) — its RTL consumers are not
wired yet; re-export `TThread` from `classes`; M5 heap *optimisation*
(per-thread arenas / lock-free fast path); M4 C `pthread` shim
([[feature-syscall-pthread-shim]]) reusing this PAL.
