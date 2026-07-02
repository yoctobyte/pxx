# Libc-free POSIX signal handler infrastructure (rt_sigaction)

- **Type:** feature (runtime / PAL) — Track A
- **Status:** backlog
- **Opened:** 2026-07-02, from the div-zero / math-error design discussion with
  the user (see [[bug-integer-div-zero-sigfpe-uncatchable]] and
  [[decide-int-div-zero-behavior-unification]]).

## Goal

PXX is libc-free, so installing a signal handler means raw `rt_sigaction` +
the kernel signal-return contract, per target:

- `rt_sigaction(2)` syscall wrappers (x86-64 = 13, i386 = 174, arm32 = 174,
  aarch64 = 134, riscv = 134), 8-byte kernel sigset.
- `SA_RESTORER` / signal trampoline: x86-64 and arm32 require a userspace
  restorer stub that calls `rt_sigreturn` (x86-64 = syscall 15); aarch64/riscv
  use the kernel vdso path. This is the delicate part — get it wrong and every
  delivered signal corrupts the process.
- Handler ABI: `void handler(int sig, siginfo_t*, ucontext_t*)` with
  `SA_SIGINFO` — ucontext gives register state (needed to resume-or-redirect
  after a fault, e.g. converting a trap into a raise).
- Interaction with `--threadsafe` / clone(2) threads (signal masks are
  per-thread; handler table is process-wide).

## Why (consumers, in priority order per user discussion)

1. **Float exception traps** ([[feature-float-exception-mask-control]]): FPC
   unmasks FPU exceptions by default; emulating that (opt-in for us — user
   prefers quiet IEEE inf/NaN propagation as the default) requires catching
   SIGFPE and converting it to a runtime error / raised exception.
2. **Div-zero without pre-checks**: an alternative detection path on x86 (not
   needed now — the pre-divide check landed — but a handler would also catch
   the still-unguarded `Low(Int64) div -1` overflow trap).
3. **Diagnostics**: SIGSEGV → "segmentation fault at $ADDR in proc X" instead
   of a bare core dump; SIGINT cleanup hooks; a future `SetSignalHandler`-style
   user API.

## Scope notes

- Start x86-64 only (host), design the wrapper API portable
  (`PalSignalInstall(sig, handler)`-shape in the PAL layer, or builtin).
- "Convert trap into Pascal exception" = modify ucontext RIP to point at a
  raise stub before returning — document carefully; that mechanism is what
  makes SIGFPE/SIGSEGV *recoverable* rather than merely reported.
- Test via `kill(getpid(), SIGUSR1)`-style self-signal plus a real SIGFPE
  (INT_MIN div -1, which the div-zero pre-check deliberately does not guard).

## Acceptance

Install a handler for a chosen signal libc-free on x86-64; handler runs and
process resumes correctly (restorer works under strace scrutiny); works with
--threadsafe; smoke test in make test.
