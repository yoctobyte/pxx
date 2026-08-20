---
track: A
prio: 45
type: feature
blocked-by: []
summary: "Cloned threads get a TLS block automatically (the clone stub carves and installs one), but the MAIN thread does not: it starts with fs base 0, so __pxxTlsBase faults there unless the program installs a block itself. Blocks any runtime fast path that wants per-thread state on all threads -- the per-thread allocator magazine first."
status: done
owner: claude-A
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

## 2026-08-20 — RESOLVED, without the shared startup emitter this ticket asked for

### The "no shared hook" problem dissolved once the entry point was checked

The plan above was "a shared emitter plus one call per frontend driver", and the
driver list is long — Pascal, C, NilPy, BASIC, e, Rust, Zig, Ada, F90, Algol,
Erlang, Lol, Whitespace. Adding a call to each is the shape that produced
`bug-a-threadsafe-segfaults-on-every-nilpy-program`, and it would have had to be
re-added to every future frontend.

**The ELF entry point is code offset 0** (`elfwriter.inc`: `entry := LOAD_ADDR +
codeOffset + AsmEntryOff`, and `AsmEntryOff` is 0 for everything but `.asm`).
Every driver's first emission is its `jmp` over its stub region — so code emitted
*before* any driver runs sits at offset 0 and executes first, on every frontend,
from **one** call site in `compiler.pas`. The driver's `jmp` follows it and is
still the first branch; nothing about the stub layout changes.

So `EmitTlsMainInstall` is six instructions and one call, not thirteen calls and
a rule for the fourteenth frontend.

### What it does

Allocates `BSS_TLS_MAIN` (`TLS_BLOCK_SIZE`) **inside the emitter**, next to the
only code that touches it — the `BSS_IO_OWNER` lesson, which had already bitten
twice. BSS is zero-filled, so only the self-pointer store and the
`arch_prctl(ARCH_SET_FS)` are emitted.

**Unconditional on x86-64**, not gated on `--threadsafe`, which is what this
ticket recommended and the recommendation held up: it is two stores and a syscall
at startup, and gating it would make `__pxxTlsBase` mean one thing in one mode and
fault in the other — a mode-dependent difference in exactly the place nobody
tests. `.asm` is skipped: its program *is* the emitted bytes and its entry point
is overridable.

### Verified

`test/test_tls_base.pas` gained phase 0 — the main thread, installing nothing:
base non-nil, slot 0 = its own address, slots 1..15 zero. Plus a standalone
program with no `uses` and no `--threadsafe` reading and writing a slot, which is
the case that faulted before this.

Frontend sweep, since this changes the first bytes of every x86-64 binary: NilPy,
C, Rust, Zig and BASIC hello-worlds all still run; `test_asm_entry_global` still
exits 42 (the `.asm` skip working); the four cross targets still build. Existing
thread suite green.

### Follow-up now unblocked

The free win this ticket recorded is real and still waiting: `EmitIoLockStubs`
does a **`gettid` syscall per I/O statement** to identify the lock owner. Every
thread now has a block, so that becomes a load — filed as
[[feature-a-io-lock-owner-from-tls-not-gettid]].

### Gate

`make compiler/pascal26` (byte-identical fixedpoint, converged in 2 rounds) +
`tools/gate.sh quick` + the sweep above.

## Log
- 2026-08-20 — resolved, commit cd7e4aae3.

## 2026-08-21 — CORRECTION: the block is in `gs`, not `fs`

The write-up above says `arch_prctl(ARCH_SET_FS)` and `mov rax, fs:[0]`. That is
what landed and it was **wrong**: glibc and musl keep *their* thread pointer in
`fs`, so a pxx program linking libc (`external 'libc.so.6'` is supported) lost
errno, the stack-protector canary at `fs:0x28`, locale and stdio the moment the
entry code ran. A four-line program calling `printf`/`malloc`/`strerror`
segfaulted before printing anything, while `pinned` ran it fine.

Nothing caught it before the push: no test in the quick tier links glibc, and
`test_multithreading` — which links libpthread — survived by luck, its calls
happening not to touch the clobbered fields.

Fixed the same night by moving to **`gs`**, which userspace does not use on
x86-64 Linux, so the two thread pointers coexist. `test/test_glibc_tls_coexist.pas`
is the regression test and is deliberately not `--threadsafe`: this is about
every build. Left the account above as written rather than editing it — it is the
record of what was actually done.
