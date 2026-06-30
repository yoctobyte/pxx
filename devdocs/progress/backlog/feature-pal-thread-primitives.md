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
