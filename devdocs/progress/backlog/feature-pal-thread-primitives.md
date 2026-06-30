# PAL thread primitives — libc-free clone(2)/futex(2) (M1 keystone)

- **Type:** feature (RTL / PAL — runtime) — Track A
- **Status:** backlog
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
