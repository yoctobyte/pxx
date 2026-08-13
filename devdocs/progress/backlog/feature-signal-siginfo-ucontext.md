---
track: A
prio: 55
type: feature
blocked-by: []
---

# Signal handlers, phase 2: SA_SIGINFO + ucontext, threadsafe masks, sigaltstack, FPC-compat surface

- **Type:** feature (runtime / PAL) — Track A
- **Status:** working
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

1. **SA_SIGINFO + ucontext.** *(x86-64 access half DONE 2026-08-13 — the flag is
   set, si_code/si_addr/ucontext* are readable via `__pxxSigCode`/`__pxxSigAddr`/
   `__pxxSigContext`. What REMAINS here: the RIP rewrite that turns a fault into
   a catchable raise, and the same treatment for the other four targets.)*
   Handler sees `siginfo_t` + register state
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

## Progress — slice 1 landed (x86-64 SA_SIGINFO + siginfo/ucontext access), 2026-08-13

Item 1's **x86-64 half**. Items 2-5 (threadsafe masks, sigaltstack, FPC-compat
`Signal()` surface, SIGPIPE policy) and the other four targets are untouched —
this ticket stays open for them.

### What landed

- The x86-64 install stub sets **SA_SIGINFO** (flags `$14000004`), so the
  kernel passes `siginfo_t*` in rsi and `ucontext_t*` in rdx.
- The dispatch stub **parks si_code / si_addr / the ucontext pointer** in three
  new BSS slots before doing anything else, while the kernel's argument
  registers are still live.
- `__pxxSigCode` / `__pxxSigAddr` / `__pxxSigContext` read them — zero-arg
  reserved-prefix intrinsics, the same shape as `__pxxExceptAddr`.

### Why the hook ABI did NOT change

The hook stays a **parameterless** Pascal proc, so every existing
`SetSignalHandler` user keeps working untouched (verified: all three existing
signal tests unchanged, including the no-hook SIG_DFL revert path that exits
143). Handing the fault data through slots rather than through new hook
parameters is what makes this slice additive instead of breaking.

### Cost in the backends: zero

`AN_SIGINFO` lowers to **IR_EXC_STORE**, whose `IRC` already selects among
status slots via `IRExcStoreSlot` — extended from 2 slots to 5. All six
backends route that op through that one function, so none of them changed.
(The op keeps its exception-era name; what it means now is "load a
compiler-owned status slot", worth renaming if a fourth family appears.)

### Verified, both values against an oracle

```
segv code=1              SEGV_MAPERR
segv addr=3735879680     = $DEAD0000, the address the test deliberately wrote
ctx set=TRUE
usr1 code=-6             SI_TKILL, via tkill(gettid(), SIGUSR1)
```

`si_addr` is asserted against the address the program itself faulted on, so a
wrong union offset cannot pass by accident. The SIGUSR1 half exists for the
**negative** code: `si_code` is a signed 32-bit field and a zero-extended load
answers 4294967290 for SI_TKILL — the mini-assembler has no `movsxd`, so the
stub sign-extends with an `shl 32` / `sar 32` pair. A C program doing the same
two syscalls agrees (`code=-6`). New test `test/test_signal_siginfo.pas`, wired
into `make test`.

### The other targets REFUSE rather than answering 0

`__pxxSig*` is a compile-time Error on aarch64/i386/arm32/riscv32 and under
`--no-signals`. Their handlers are installed without SA_SIGINFO, so the slots
are never written, and a plausible `0` ("SI_USER", "no fault address") is the
silent wrong value this dialect refuses to invent — same call the ESP PAL makes
with `PAL_ERR_UNSUPPORTED`. Confirmed all four still compile ordinary signal
code unchanged.

### The b371 landmine is intact and still applies

i386 and arm32 pick the signal FRAME SHAPE by SA_SIGINFO, not by which syscall
installed the handler, and their restorers still call **sigreturn (119)**.
Whoever does those targets MUST flip them to **rt_sigreturn (173)** in the same
change or the kernel restores a garbage context (pc=sp=lr=0). Nothing here
touches their install sites, which is exactly why this slice is x86-64-only.

### What this unblocks

[[feature-float-exception-mask-control]] is now implementable — si_code is the
only carrier of which float exception fired (the MXCSR status flags read 0x00
in a handler because Linux hands it a clean FP state; measured, see that
ticket). Its `blocked-by` should be cleared only once whoever picks it up is
happy with x86-64-only, since `__pxxSigCode` refuses elsewhere.

Still NOT done, and needed for the *catchable* fault work
([[bug-integer-div-zero-sigfpe-uncatchable]],
[[decide-int-div-zero-behavior-unification]]): the ucontext pointer is parked
but nothing rewrites the saved RIP yet. That is the rest of item 1.
