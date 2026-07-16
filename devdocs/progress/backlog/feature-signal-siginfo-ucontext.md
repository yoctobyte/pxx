---
prio: 55
---

# Signal handlers, phase 2: SA_SIGINFO + ucontext, threadsafe masks, sigaltstack, FPC-compat surface

- **Type:** feature (runtime / PAL) — Track A
- **Status:** backlog
- **Opened:** 2026-07-16, split out of [[feature-signal-handlers]] once the base
  slice (libc-free `rt_sigaction` handler install + `SetSignalHandler`) shipped
  and pinned on all five hosted targets (x86-64 b336, aarch64 b370,
  i386/arm32/riscv32 b371).

## Context

The base ticket's acceptance is met and pinned: install a parameterless Pascal
hook libc-free on every hosted Linux target; delivered signal calls it and the
program resumes; no-hook -> SIG_DFL + re-raise -> exit 143; `--no-signals` opts
out; smoke tests wired into each arch's suite. This ticket carries the scope the
base ticket explicitly deferred — the recoverable-fault machinery and the
niceties around it.

## Remaining work

1. **SA_SIGINFO + ucontext.** Handler sees `siginfo_t` + register state
   (`ucontext_t`). This is the load-bearing piece for turning a fault into a
   *catchable* Pascal raise: modify ucontext RIP/PC to point at a raise stub
   before returning. Consumers: div-zero unification
   ([[decide-int-div-zero-behavior-unification]],
   [[bug-integer-div-zero-sigfpe-uncatchable]]), the float-exception-mask trap
   path ([[feature-float-exception-mask-control]]), and SIGSEGV/SIGBUS
   diagnostics ("fault at $ADDR in proc X").
   - **LANDMINE from b371:** arm32 and i386 pick the signal-frame shape by
     SA_SIGINFO, NOT by which sigaction syscall installed the handler. The
     current no-SA_SIGINFO restorers call **sigreturn (119)**. The moment
     SA_SIGINFO is set these MUST flip to **rt_sigreturn (173)** or the kernel
     restores a garbage context (observed as pc=sp=lr=0 -> instant SIGSEGV).
     aarch64/riscv32 use the kernel vdso path either way.

2. **--threadsafe interaction.** Signal masks are per-thread; the hook table is
   process-wide. Define + test delivery under clone(2) threads (which thread
   runs the handler, mask inheritance).

3. **sigaltstack.** Today a guard-page fault reuses the faulting stack — fine
   for a benign hook, fatal for a stack-overflow fault. Install an alt stack so
   SIGSEGV-on-guard-page is handleable.

4. **FPC-compat surface.** `Signal()` / sigaction-shaped API mirroring FPC for
   corpus compatibility (the base ticket shipped only the native
   `SetSignalHandler` intrinsic).

5. **SIGPIPE policy** (revisit with the net library) — base ticket deliberately
   left it NOT default-ignored so a write-loop program dies on closed stdout.

## Gate

Per touched target: the fault-to-raise path catches a real SIGFPE
(`Low(Int64) div -1`) and SIGSEGV and converts to a Pascal exception; existing
signal smoke tests stay green; self-host byte-identical; cross suites green.
