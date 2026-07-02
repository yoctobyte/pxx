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

## Why (consumers — this is GENERAL signal infrastructure, not a math-error
   helper; math traps are just one client. Scope per user 2026-07-02.)

1. **Graceful termination**: SIGINT (Ctrl-C) and SIGTERM (system shutdown,
   `kill`, service managers) → run cleanup hooks (flush files, release locks,
   restore terminal state — ansiterm/lineedit/TUI programs currently leave the
   terminal raw on Ctrl-C) before exiting, and a user-facing API to register
   handlers (`SetSignalHandler(SIGINT, @MyProc)` / FPC-compatible surface).
   Long-running demos/servers (http, dns, scheduler) are the immediate users.
2. **SIGPIPE**: networking code (net/sockets/tls/http) dies silently on a
   closed peer today unless every write is guarded; standard practice =
   ignore SIGPIPE process-wide and surface EPIPE as an error return.
3. **Float exception traps** ([[feature-float-exception-mask-control]]): FPC
   unmasks FPU exceptions by default; emulating that (opt-in for us — user
   prefers quiet IEEE inf/NaN propagation as the default) requires catching
   SIGFPE and converting it to a runtime error / raised exception.
4. **Math traps not worth pre-checking**: the still-unguarded
   `Low(Int64) div -1` overflow trap; an alternative div-zero path on x86
   (pre-divide check already landed, v135).
5. **Diagnostics**: SIGSEGV/SIGBUS → "segmentation fault at $ADDR in proc X"
   instead of a bare core dump (huge for self-host debugging); SIGCHLD if
   process spawning ever lands.

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

## Constraints (user, 2026-07-02)

- **Minimal-hello-world budget**: handler install is boilerplate (rt_sigaction
  calls + restorer stub + handler code) — it must NOT be unconditionally baked
  into every binary. Emit/link only when something actually consumes it (float
  mask opt-in, a user SetSignalHandler call, a diagnostics flag), and provide
  an explicit opt-out for whatever default is chosen. Follow the existing
  needsHeap/needsAnsiRuntime detection pattern: pay only when used. Pin the
  minimal hello-world code size in a test if a default-on consumer ever lands.
- **PC (Linux) platforms only**: x86-64 / i386 / arm32 / aarch64 Linux.
  ESP targets (xtensa/riscv32 bare-metal) have no kernel, no signals — the
  API must compile away / hard-error cleanly there, and any codepath whose
  behavior differs with signals installed (e.g. a blocking read returning
  EINTR, float traps vs quiet NaN) must keep its no-signals behavior on those
  targets. Document the divergence per codepath as they appear.
