# PAL thread primitives — libc-free clone(2)/futex(2) (M1 keystone)

- **Type:** feature (RTL / PAL — runtime) — Track A
- **Status:** done
- **Opened:** 2026-06-30
- **Umbrella:** [[meta-multithreading]]. Unblocks M2/M3/M4.

## Invariant (all multithreading tickets)

**Self-host is single-threaded and stays that way.** Every threading feature is
**opt-in** (a `uses`/flag/directive), **off by default**, and MUST NOT change the
single-threaded self-build — which stays **byte-identical** (the gate). Because of
this, milestones can land in **any order**; nothing here is allowed to perturb the
default single-threaded path. **No libc** — Linux syscalls only.

## Scope (Linux/x86-64 first; cross later under M5)

The green-field foundation everything else sits on. Raw syscalls, no libc:

- `PalThreadCreate(entry, arg) -> handle`: `clone(2)`/`clone3` with
  `CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|
  CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID`. PXX-owned **mmap'd
  stack** (+ a `PROT_NONE` guard page); a small **start trampoline** that calls
  the Pascal entry and `exit(0)`s the thread (never returns onto a torn stack).
- `PalThreadJoin(handle)`: futex-wait on the **child-tid** word
  (CLONE_CHILD_CLEARTID writes 0 + futex-wakes on exit).
- `PalFutexWait(addr, expected)` / `PalFutexWake(addr, n)` over `SYS_futex`.
- `PalThreadSelf`, and per-thread storage if needed (TLS via CLONE_SETTLS /
  arch_prctl — only if a consumer requires it).

## Notes / risks
- The Pascal entry runs on the new stack — the runtime it touches must be honest
  (heap/IO contract, M0) before this is "production". Building + unit-testing the
  primitive itself does NOT require M0 (a thread that only does syscalls/local work
  is safe), so scaffold first.
- Keep it a thin PAL surface; TThread / pthread-shim are separate façades.

## Acceptance
- A libc-free test spawns N threads that each do local work + futex-synchronise,
  joins them, correct result, **zero `DT_NEEDED`** (no libc/libpthread).
- Single-threaded self-build byte-identical (opt-in; default path untouched).

## Technical scope — de-risked (2026-06-30)

Survey result: the RTL already has `__pxxrawsyscall(num, a1..a6)` (compiler-
intercepted, used by ansiterm/baseunix). So most of M1 is **pure Pascal, no
compiler change**:
- **futex** = `__pxxrawsyscall(SYS_futex=202, uaddr, op, val, ts, uaddr2, val3)`.
- **mmap** thread stack + `mprotect` guard page = `__pxxrawsyscall`.
- **thread exit** = `__pxxrawsyscall(SYS_exit=60, 0,...)`.

**The one real compiler change = a `__pxxclone` builtin.** `clone(2)` can't go
through `__pxxrawsyscall`: after the syscall the **child** resumes *inside*
`__pxxrawsyscall` on the fresh stack and would `ret` through a torn frame. The
child must instead branch on `rax==0`, set up args from the new stack, `call` the
Pascal entry, then `SYS_exit` — never returning to Pascal. pxx inline-asm has no
branches/labels yet ([[feature-inline-asm-depth]]), so emit the trampoline as a
compiler builtin (intercept like `__pxxrawsyscall`, ~35 bytes x86-64):

```
; __pxxclone(flags, childStackTop, ptid, ctid, tls, entry, arg) -> tid
; pre-push [entry][arg] at childStackTop; rdi=flags rsi=stack rdx=ptid r10=ctid r8=tls
mov eax, 56            ; SYS_clone
syscall
test rax, rax
jnz  .parent          ; parent: rax = child tid -> return
pop  rax              ; child: entry (was pushed)
pop  rdi              ; arg
call rax              ; run Pascal entry(arg) on the new stack
xor  edi, edi
mov  eax, 60          ; SYS_exit
syscall
.parent:
; rax already = tid
```

`PalThreadJoin` = futex-wait on the CLONE_CHILD_CLEARTID word (kernel writes 0 +
wakes on exit). First slice: x86-64 only; cross trampolines under M5.

**Implementation order (each testable):** (1) futex + mmap-stack PAL (pure Pascal);
(2) the `__pxxclone` builtin (compiler, x86-64); (3) `PalThreadCreate/Join` +
trampoline glue; (4) a libc-free test: N threads incrementing a shared counter
under a futex mutex, join, assert no lost updates, `ldd`/`readelf -d` shows no
libc/libpthread. Opt-in target; single-thread self-build byte-identical.

## Status — M1 first slice LANDED (2026-06-30, commit a49d5251)

DONE (x86-64):
- `__pxxclone(flags, childStack, entry, arg, ctidptr)` intrinsic — AN_CLONE(72) ->
  IR_CLONE(62) -> bare clone(2)+trampoline stub (compiler/thread_emit.inc), emitted
  lazily with a jmp-over so it works from main program OR a uses'd unit.
- `lib/rtl/palthread.pas`: PalThreadCreate / PalThreadJoin / PalFutexWait /
  PalFutexWake / PalThreadSelf. mmap'd stacks, race-free futex join via
  CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, munmap on join.
- Tests: test_thread_clone (raw) + test_palthread (PAL), `make test-threads` gate.
  Single-thread self-host byte-identical; full `make test` green; libc-free
  (readelf -d shows no libpthread).

REMAINING in M1:
- i386 trampoline (SYS_clone=120, int 0x80, args on stack) — currently a clean
  compile-error. The goal is "main platforms (PC/server/intel/AMD)"; x86-64 covers
  the 64-bit case, i386 is the 32-bit follow-up.
- TLS: child shares the parent fs base (no CLONE_SETTLS yet). Fine for the
  global-state RTL; per-thread TLS is needed before thread-local vars / a
  per-thread exception chain (ties into [[audit-shared-global-reentrancy-thread-safety]]).
- Stack guard page (mprotect PROT_NONE at the low end) — overflow currently just
  faults into adjacent mmap. Cheap to add.

NEXT MILESTONE: M2 futex sync primitives ([[feature-sync-primitives-futex]]) now
has its foundation (PalFutexWait/Wake live).

## Update — M1 remainder closed (2026-07-03, Track A)

- **Stack guard page**: DONE. PalThreadCreate mmaps stackSize+4096 and
  mprotects the LOW page PROT_NONE; overflow now faults immediately instead
  of scribbling into the adjacent mapping. StackSize records the full
  mapping so Join's munmap releases the guard too. Verified: test_palthread
  4/4 + full make test-threads green.
- **i386 trampoline**: MECHANISM DONE + verified. __pxxclone int-0x80 stub
  in thread_emit.inc (stack-arg contract, ebx/esi/edi preserved; LANDMINE:
  i386 clone's tls/ctid registers are SWAPPED vs x86-64's r10/r8 order),
  IR_CLONE + 32-bit IR_ATOMIC in ir_codegen386.inc (LANDMINE found: the 386
  IR walker's `else IREmitNode386(i)` fallback double-executed value ops —
  IR_ATOMIC/IR_CLONE added to the operands-skip list, mirroring x86-64's
  whitelist), i386 syscall numbers in palthread.pas. A 4-thread × 100k
  futex-mutex counter ran exactly (400000) under qemu-i386 with the
  --threadsafe guard temporarily bypassed (bypass reverted). The i386
  atomics regression (test_atomic_i386 vs x86-64 golden) is in
  make test-i386. End-to-end i386 threading stays gated on the runtime
  locks — split to [[feature-i386-threadsafe-locks]] (heap spinlock, ARC
  lock-dec, I/O owner lock: genuinely bigger than this ticket's remainder).
- **TLS**: deliberately NOT done. The original scope made it conditional
  ("only if a consumer requires it") and no consumer exists — pxx has no
  thread-local vars and the RTL is global-state. Revisit with a
  thread-local-vars ticket; CLONE_SETTLS + arch_prctl is the noted shape.

M1 closed; the i386 lock leg lives in its own ticket.
