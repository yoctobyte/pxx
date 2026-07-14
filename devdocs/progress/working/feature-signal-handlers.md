---
prio: 65  # auto
---

# Libc-free POSIX signal handler infrastructure (rt_sigaction)

- **Type:** feature (runtime / PAL) — Track A
- **Status:** working
- **Owner:** fable-nightA
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

- **Default ON, opt-out, NO auto-detection** (user, revised 2026-07-02):
  signal support is enabled by default on PC targets — no needsHeap-style
  feature sniffing to decide whether to emit it; predictable behavior beats
  cleverness here (Ctrl-C/SIGTERM handling should just work in every normal
  binary). A single explicit `--no-signals` (or similar) opts out entirely
  for the minimal-hello-world case. Keep the default install lean (the
  boilerplate is rt_sigaction calls + restorer stub + a small dispatch
  handler — measure and record what it costs hello world; pin the opted-out
  size in a test).
- **PC (Linux) platforms only**: x86-64 / i386 / arm32 / aarch64 Linux.
  ESP targets (xtensa/riscv32 bare-metal) have no kernel, no signals — the
  API must compile away / hard-error cleanly there, and any codepath whose
  behavior differs with signals installed (e.g. a blocking read returning
  EINTR, float traps vs quiet NaN) must keep its no-signals behavior on those
  targets. Document the divergence per codepath as they appear.

## Progress — 2026-07-02, first slice LANDED (x86-64, v136)

Core infrastructure + user API live on the primary target:

- **Stubs** (`EmitSignalRuntime`, ir_codegen.inc, all EmitAsmX64): restorer
  (`rt_sigreturn` — x86-64 requires SA_RESTORER), dispatch (kernel plain-
  handler ABI, edi=sig; hook table lookup → `call hook`; no hook → rebuild
  struct sigaction to SIG_DFL + re-raise via kill(getpid,sig), so unhandled
  managed signals still die with proper killed-by-signal status), sethook
  (edi=sig, rsi=handler → store BSS_SIG_HOOKS slot, falls through) + install
  (edi=sig → rt_sigaction with {dispatch, SA_RESTORER|SA_RESTART, restorer,
  0}). Code-absolute addresses inside structs via call/pop trick
  (`EmitCodeAbsToRdx`) — position-independent, no new reloc kind.
- **Default-on**: entry installs dispatch for SIGINT(2) + SIGTERM(15) before
  unit inits. `--no-signals` opts out (no stubs, no installs; SetSignalHandler
  then a clean compile error). **Measured cost: 272 bytes on hello world.**
- **User API**: `SetSignalHandler(sig, @proc)` soft intrinsic (parser →
  AN_SET_SIGNAL(76) → IR_SET_SIGNAL(65) → SigSetHook call). Parameterless
  hooks, any signal 1..64 (installs on demand beyond the default set);
  `SetSignalHandler(sig, nil)` reverts to default on next delivery. Hooks run
  in signal context — kernel restores the full register file on return;
  SA_RESTART keeps interrupted blocking syscalls transparent. Caveat
  (documented): hooks that touch the heap/managed strings while the main
  program is mid-allocation are unsafe (heap spinlock deadlock under
  --threadsafe) — set flags, do work in the main loop.
- Gate: test/test_signal_handlers.pas (hooks fire ×3 signals, program
  survives, nil-revert dies 143) in make test; suite green; self-host
  converged; pinned v136.

**Remaining** (this ticket stays open): i386/arm32/aarch64 (per-target
sigaction layouts + restorer conventions), SIGPIPE policy for the net stack
(decided NOT default-ignored for now — a write-loop program must die on
closed stdout; revisit with the net library), sigaltstack (hook on a guard-
page fault reuses the faulting stack today), thread interaction beyond
"handler table is process-wide", FPC-compat `Signal()`/sigaction surface,
and the float-mask consumer ([[feature-float-exception-mask-control]]).


## 2026-07-14 — the x86-64 handler slice is DONE and now PINNED (b336)
Auditing this ticket found the "remaining" work largely shipped already and
DEFAULT-ON for x86-64 Linux (ir_codegen.inc's signal stubs: SA_RESTORER
trampoline -> rt_sigreturn, a dispatch stub with a 64-slot BSS hook table,
SetSignalHandler as a compiler intrinsic; --no-signals opts out). It had NO
test. Verified and pinned tonight:

- `SetSignalHandler(sig, @proc)` installs a parameterless Pascal hook; a
  delivered SIGTERM/SIGINT calls it and the program RESUMES at the
  interruption point (kernel restores the register file through our restorer).
  -> test/test_signal_handler_callback_b336.pas
- No hook for a managed signal: dispatch reverts to SIG_DFL and re-raises, so
  an unhandled SIGTERM still dies with status 143.
  -> test/test_signal_default_revert_b336.pas (asserted by exit status)

`PalGetpid` surfaced in platform.pas (the backend always had it).

### What actually remains
- The SAME slice on i386/arm32 (need their own restorer stubs; aarch64/riscv
  use the kernel vdso path) — the delicate per-arch part.
- SA_SIGINFO + ucontext (handler sees siginfo/register state) — needed to turn
  a fault into a catchable raise; the div-zero unification consumer.
- Interaction with --threadsafe (per-thread masks).

## 2026-07-14 — AARCH64 slice DONE (b370)

The per-arch port the ticket flagged as "the delicate part". aarch64 is NOT a
copy of the x86-64 stubs — two contract differences, both load-bearing:

- **No SA_RESTORER.** arm64 does not define `__ARCH_HAS_SA_RESTORER`, so the
  kernel `struct sigaction` is `{ handler(8), flags(8), mask(8) }` — no
  restorer field, and **sa_mask sits at offset 16**, not 24. The kernel
  supplies the sigreturn trampoline itself (lands in x30). Setting
  SA_RESTORER here would have written the flag into the mask.
- **x30 must be framed across the hook call.** x86-64's return address is on
  the stack (`call hook; ret` is naturally safe); on aarch64 `blr` clobbers
  x30 = the kernel trampoline, so dispatch does stp/ldp around it.

Syscalls: rt_sigaction=134, getpid=172, kill=129. Every instruction's hex was
verified against `aarch64-linux-gnu-as` (including the branch offsets — the
first cut had three wrong, computed against a layout that omitted the 3-word
glob-load, and the symptom was the no-hook path silently resuming instead of
dying).

Both existing tests now run on aarch64 under qemu and are wired into
`make test-aarch64`: the callback path (hook fires ×2, program RESUMES at the
interruption point) and the default-revert path (no hook -> SIG_DFL + re-raise
-> exit 143).

### What remains
- i386 / arm32: both DO need a restorer stub (their own conventions) —
  i386 rt_sigreturn=173, arm32 = the sigpage/SA_RESTORER dance. riscv32 uses
  the vdso path like aarch64, so it should mirror this slice closely.
- SA_SIGINFO + ucontext (handler sees siginfo/register state) — the
  fault-to-catchable-raise consumer.
- --threadsafe interaction (per-thread masks).
