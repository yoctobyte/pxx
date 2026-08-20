---
track: A
prio: 53  # auto
owner: ""
---

# Threadsafe heap — optimize + cross-target (M5)

- **Type:** feature (codegen / runtime — optimization) — Track A
- **Status:** unfinished — the lock half, the benchmark and the TLS blocker are all done. The magazine half is PARKED with its diagnosis banked: the lock it would bypass is not only the allocator's, so it needs a design change first (see the 2026-08-21 note at the bottom).
- **Opened:** 2026-06-30
- **Umbrella:** [[meta-multithreading]]. Follows the M0 contract
  [[feature-threadsafe-heap-contract]] (correctness) — this is the *speed* half.
- **Relation:** correctness-over-speed (user rule) — do AFTER the contract holds.

## Invariant

Threading is **opt-in**, off by default; the single-threaded self-build stays
**byte-identical**. **No libc** — built on [[feature-pal-thread-primitives]]
(syscalls only). Milestones land in any order under [[meta-multithreading]].

## Scope

Today `--threadsafe` = a coarse global `lock`-prefix on every alloc/free +
refcount, **x86-64 only**. Make it fast + portable:
- **Per-thread heap arenas** (or a lock-free free-list fast path) so uncontended
  alloc/free doesn't serialise on one global lock.
- **Cross-target the threadsafe atomics** — i386/arm32/aarch64/riscv32 currently
  reject `--threadsafe` (only x86-64 has the lock prefix). Add LL/SC / `ldrex`/
  `amoadd` equivalents.
- Benchmark alloc throughput single- vs multi-thread; guard against regression.

## Acceptance
- Multi-thread alloc benchmark scales (no single-lock cliff); `--threadsafe`
  accepted + correct on the cross targets; single-thread alloc unchanged; self-host
  byte-identical.

## Update — thread-safe heap VALIDATED under contention (2026-06-30)
test_thread_heap (lib/rtl + TThread): 4 threads x 12000 GetMem/FreeMem of 128B,
each fills its block with a thread-unique tag and reads it back. WITH --threadsafe:
0 errors across runs (the existing x86-64 lock-prefixed spinlock around PXXAlloc/
PXXFree holds). WITHOUT --threadsafe: SIGSEGV every run — proving threaded
allocation genuinely requires the flag (the M5 contract). In make test-threads
(compiled --threadsafe). The *optimisation* part of M5 (per-thread arenas /
lock-free fast path) is still open; correctness is now demonstrated + gated.

## 2026-08-20 — measured first; the cross-target half is largely already done, the lock half landed, the scaling half is BLOCKED

### The ticket's scope had drifted — checked before writing anything

"Today `--threadsafe` = a coarse global lock ... **x86-64 only**" was true when
this was opened on 2026-06-30. It is not true now: `compiler.pas:845` accepts
**x86-64, i386, aarch64 and arm32**, each with its own lock implementation, and
`EmitIoLockStubsForTarget` dispatches to four per-arch I/O-lock stubs. Only
**riscv32** still refuses, and riscv32 is the ESP32-C3 target — FreeRTOS, not
clone(2) threads — so `--threadsafe` there is close to meaningless. The
cross-target bullet is therefore effectively closed; what is left is the
bullet this ticket is named for.

### The benchmark the acceptance asks for now exists

`bench/threadsafe_heap_scaling.pas`, `make benchmark-threadsafe-heap`. It holds
the TOTAL allocator work constant and splits it across the threads, so flat wall
time = perfect scaling and a rise = the lock serialising. That framing is what
makes the result legible; a per-thread-fixed-iterations benchmark would have hid
the cliff behind "more threads do more work".

### The cliff was real, and part of it was pure interference

| threads | 1 | 2 | 4 | 8 |
| --- | --- | --- | --- | --- |
| `lock xchg` spin loop (before) | 66 ms | 100 ms | 132 ms | 171 ms |
| TTAS + `pause` (after) | 60 ms | 74 ms | 90 ms | 122 ms |
| | — | −26% | −32% | −29% |

Median of 3 on a 12-core box with Track T also running — ratios, not absolutes.
Full write-up: `benchmarks/2026-08-20-threadsafe-heap-lock.md`.

`EmitAcquireHeapLock` was a bare `lock xchg` loop, which performs an atomic
read-modify-write on *every* spin and so takes the lock's cache line exclusive
each time — while the **holder** needs that same line to finish and release.
Waiters were slowing down the work they were waiting for, which is why the curve
grew faster than the thread count. Test-and-test-and-set spins on an ordinary
load and only attempts the atomic when the lock looks free; `pause` throttles
the loop and yields to a hyperthread sibling. (`pause` was not in the text
assembler; added as `F3 90`.)

**Single-thread cost is unchanged** — the uncontended path is one atomic either
way. The 66-vs-60 is noise and is not claimed as a win.

Correctness: `test_thread_heap` run **12×** and `test_thread_heap_mixed` 8×,
zero failures, plus `test_thread_heap_mixed`, `test_threadsafe_io_lock`,
`test_multithreading`, `test_tthread_sync` green. A lock change earns repetition
rather than one pass.

### The scaling half is BLOCKED, and the blocker is not in this ticket

What remains — flattening that curve — is honest serialisation: one global lock,
one thread allocating at a time. The standard fix is a per-thread free-list
magazine so uncontended alloc/free never touches the lock. **It cannot be
written, because this runtime has no thread-local storage at all:**
`PXX_CLONE_THREAD = $350F00` omits `CLONE_SETTLS`, so every thread shares the
parent's `fs` base and an `fs:`-relative slot is the same memory in every
thread. The only per-thread handle available is `gettid`, a syscall — fine at
I/O-statement granularity (where the I/O lock already uses it) and hopeless on
an allocator fast path.

Filed as [[feature-a-thread-local-storage-via-clone-settls]]. This ticket should
be considered blocked on it for the arena work; the lock and benchmark halves
are done.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) + `tools/gate.sh quick`
GREEN + the thread suite above, repeated.

## 2026-08-20 (later) — UNBLOCKED: the TLS primitive exists

[[feature-a-thread-local-storage-via-clone-settls]] resolved, and not the way it
proposed: `arch_prctl(ARCH_SET_FS)` acts on the calling thread, so no
`CLONE_SETTLS` and no sixth `__pxxclone` argument were needed. A thread installs
its own block; `__pxxTlsBase` reads it back in one instruction (`mov rax,
fs:[0]`, slot 0 = self-pointer). x86-64 only, which is where `--threadsafe`
lives anyway. See `devdocs/dev/threading.md` "Thread-local storage (x86-64)".

So the magazine is writable now. Two things to know before starting it:

1. **The install is not automatic.** (SUPERSEDED same day -- see the last
   section: the clone stub installs it now.) Nothing in the RTL installs a block yet, and
   a thread that skips it reads its PARENT's block rather than nil — the aliasing
   failure, wearing a valid-looking pointer. `palthreadobj`'s `ThreadObjLauncher`
   is the place, and it is **`lib/rtl` = Track B's file-lane**. The allocator half
   (`compiler/builtin/builtinheap.pas`, `EmitAcquireHeapLock`) is A. So this
   ticket now spans two lanes; do the B half as a B ticket or hold both lanes.
2. **The main thread needs one too**, before the first allocation, or the fast
   path faults on an fs base of 0 at the worst possible moment.

## 2026-08-20 (later still) — the TLS install is now AUTOMATIC for cloned threads

The primitive existed but was unusable in practice: nothing installed a block, and
a thread that skipped the install read its PARENT's block — not a null pointer you
could branch on, but a valid-looking pointer into someone else's storage. An
allocator magazine built on "the launcher remembers" would have been a heap
corruptor waiting for the one caller that didn't.

So the **clone stub** installs it, not the RTL. On the child path, before any
Pascal runs, it carves `TLS_BLOCK_SIZE` (128) bytes off the top of the child's
stack, zeroes them, writes the self-pointer and `arch_prctl`s the block. Every
pxx thread passes through `__pxxclone` whatever frontend or library created it,
so forgetting is now unreachable rather than merely documented — and it took the
RTL half out of Track B's lane entirely, which is a better outcome than the
two-lane split noted above.

Zeroed rather than trusted: `palthread` hands over fresh anonymous `mmap`, but
`__pxxclone` is reachable directly and a reused stack would otherwise present the
previous thread's slots as this one's. Cost to the caller: `__pxxclone` now needs
144 usable bytes of stack, against a 1 MiB default.

`test/test_tls_base.pas` grew a phase A that proves it: four children that call
`arch_prctl` **nowhere** still come back with four distinct bases, distinct from
the main thread's, each with slot 0 = its own address and slot 1 zeroed. Nothing
but the stub can have done that. Phase B keeps the manual path covered. Existing
thread suite re-verified after the stub change (`test_thread_clone`,
`test_palthread`, `test_atomic_counter`, `test_mutex`, `test_event`,
`test_critsec_once`, `test_tthread`, plus `test_thread_heap`,
`test_thread_heap_mixed`, `test_threadsafe_io_lock`, `test_multithreading`,
`test_tthread_sync` ×5 each).

### Still blocking the magazine: the MAIN thread

It passes through no stub, and a static pxx binary starts with `fs` base 0, so
`__pxxTlsBase` faults there. A fast path that faults on the main thread is not a
fast path. Filed as [[feature-a-tls-block-for-the-main-thread]] with the design
worked out — it needs a shared startup emitter, which does not exist: every
frontend driver emits its own entry sequence and only Pascal's puts anything in
it. That ticket also records the free win sitting next to this one (the
`--threadsafe` I/O lock does a `gettid` **syscall per I/O statement**, which a TLS
slot turns into a load).

So the order is: main-thread block -> magazine. This ticket stays open on the
magazine and is no longer two-lane.

## 2026-08-21 — the magazine is bigger than this ticket says, and here is why

TLS is no longer the blocker (every thread has a block now). So I went to write
the magazine and stopped at the first question: **where is the lock taken?**

### The lock is not the allocator's lock

The ticket, and the summary line at the top of this file, both say "a coarse
global lock on every alloc/free". That is half of it. `EmitAcquireHeapLock` has
**19 call sites in `ir_codegen.inc` alone**, plus `symtab.inc`, and they are not
all allocator entries:

| site | what is inside the lock |
| --- | --- |
| `EmitDynArrayRetain` | refcount increment |
| `EmitDynArrayReleaseForNode` | decrement **and free if it hit zero** |
| `EmitDynArrayUnique` | read refcount, copy, swap, release |
| `symtab.inc` scope exit | release **every managed field of a record** |
| plain `GetMem` / `New` / object alloc | actual allocator state |

Only the last row is what a magazine can bypass. The others hold the lock to
make a **compound** operation atomic — "decrement, and if that reached zero,
free" is not two independent atomics, and the record-scope-exit site walks a
whole field list inside one critical section. (The bare refcount bumps that
*don't* free already use `lock dec` and skip the lock entirely, so the
distinction is one the codegen already draws — just not where the ticket
assumes.)

### What that means for the work

A per-thread magazine cannot be written inside `builtinheap.pas` and left at
that: on x86-64 the lock is taken by **codegen, outside the call**, so a
magazine hidden in `PXXAlloc` would run with the lock already held and buy
nothing. (Note `PXX_TS_SOFTLOCK` — the i386 path — does the opposite and takes
the lock *inside* the allocator. Two mechanisms for one concept, which
`normalise-dont-special-case.md` calls a smell, and it is: whichever way this
lands, the two paths should end up the same shape.)

So the real job is, in order:

1. **Separate the two roles.** The allocator-state lock and the
   managed-refcount critical section are one lock doing two jobs. Splitting them
   is the actual root fix and is what makes everything below possible.
2. A magazine fast path at the **pure alloc/free** sites only — TLS load, size
   class, list pop, zero, fall back to lock + `PXXAlloc` on a miss. Hand-emitted
   x86-64 at each site, or one lock-free stub they all call.
3. Then measure against `bench/threadsafe_heap_scaling.pas`, which already
   exists and already shows the cliff.

Step 1 is a Track A design change with the self-host gate over it, not an
afternoon. **Parked with the diagnosis banked rather than microfixed** —
`root-cause-over-microfix.md`'s explicit instruction for this situation, and the
microfix here (a magazine that skips a lock it does not in fact hold) would be
worse than nothing, because it would look like it worked.

Where the remaining measured speed actually is, for whoever picks this up: the
lock half already took 26-32% off the contended path (see the table above), and
[[feature-a-io-lock-owner-from-tls-not-gettid]] removes a **syscall per I/O
statement**, which is a bigger constant than anything left in the allocator.
