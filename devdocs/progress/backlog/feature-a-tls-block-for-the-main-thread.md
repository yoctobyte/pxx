---
track: A
prio: 45
type: feature
blocked-by: []
summary: "Cloned threads get a TLS block automatically (the clone stub carves and installs one), but the MAIN thread does not: it starts with fs base 0, so __pxxTlsBase faults there unless the program installs a block itself. Blocks any runtime fast path that wants per-thread state on all threads -- the per-thread allocator magazine first."
status: backlog
owner: ""
---

# The main thread has no TLS block

- **Track A** — needs a shared emitter plus one call per frontend driver.
- Split out of [[feature-a-thread-local-storage-via-clone-settls]] while landing
  the automatic install, 2026-08-20.

## State

`__pxxTlsBase` reads `fs:[0]`. Every thread created through `__pxxclone` has a
block, because the clone stub carves 128 bytes off the top of the child stack,
zeroes it, writes the self-pointer and `arch_prctl(ARCH_SET_FS)`s it before any
Pascal runs (`compiler/thread_emit.inc`).

The main thread passes through no stub. A static pxx binary starts with `fs`
base **0**, so `__pxxTlsBase` on the main thread **faults** unless the program
installs a block itself — which `test/test_tls_base.pas` does, and which no
ordinary program should have to.

## Why it was not done in the same slice

There is no shared "emit program-startup code" hook. Each frontend driver emits
its own entry sequence, and only the Pascal one
(`compiler/pasparser_prog.inc`) emits anything there at all — the SIGINT/SIGTERM
installs. `EmitIoLockStubsForTarget` is the shared threadsafe-init call every
driver already makes, but it runs in the STUB region, behind the entry `jmp`, so
it cannot emit code that executes.

(Checked while filing this, so it does not get re-derived: the other frontends
missing the startup signal install is **not** a bug. With no hook registered the
dispatch stub reverts and re-raises, so an uninstalled SIGINT kills with the same
status — measured, both a `.pas` and a `.npy` build exit 130 on Ctrl-C.)

## Shape of the work

1. `EmitTlsMainInstallForTarget` next to `EmitIoLockStubsForTarget`: allocate
   `BSS_TLS_MAIN` (`TLS_BLOCK_SIZE` bytes) **in that procedure**, not in a
   driver — the `BSS_IO_OWNER` lesson, which has now bitten twice.
2. One call per driver at the point where the main body starts (Pascal, C,
   NilPy, BASIC, e, Rust, Zig). That is the sanctioned shape, not the
   antipattern: the antipattern was each driver spelling out the per-arch
   choice, and the fix was "a single call, not a ninth copy".
3. BSS is already zero, so only the self-pointer store plus the `arch_prctl` are
   needed — about six instructions.

Gate it under `ThreadSafeMode` only, or unconditionally? **Unconditionally on
x86-64 is the better call** and should be confirmed by measurement: it is two
stores and one syscall at startup, it makes `__pxxTlsBase` mean the same thing
in every build, and gating it on `--threadsafe` creates exactly the kind of
mode-dependent difference that produces a plausible wrong pointer in the mode
nobody tests.

## Why it matters

The per-thread allocator magazine — the open half of
[[feature-threadsafe-heap-optimize]] — runs on the main thread too. A fast path
that faults on `fs:[0]` before `main` has installed a block is not a fast path.
Same for a future per-thread errno, exception-chain head
([[audit-shared-global-reentrancy-thread-safety]]) or RNG state.

There is also a free win waiting: the `--threadsafe` I/O lock does a `gettid`
**syscall per I/O statement** (`EmitIoLockStubs`, comment says "no TLS yet").
With a block on every thread that becomes a load.

## Gate

`__pxxTlsBase` works on the main thread of a program that installs nothing,
across frontends; `test_tls_base` still green; self-host byte-identical.
