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

## What the OTHER FOUR targets need (survey, 2026-08-13)

Written after landing x86-64 so the remaining work is a checklist, not a
rediscovery. Every arch needs the same three things — **set SA_SIGINFO in the
install stub's flags**, **park si_code/si_addr/ucontext from the handler's
argument registers into BSS_SIG_CODE/ADDR/CTX**, and **drop the per-target
`Error` guard in parser.inc's `__pxxSig*` arm** — and then each has its own
catch.

### The data layout, which is NOT the same on 32-bit

`siginfo_t` is `{ int si_signo; int si_errno; int si_code; union _sifields; }`,
so **si_code is at offset 8 everywhere**. `si_addr` is the union's first
member, and the union is pointer-aligned, so the preamble is padded on 64-bit
(`__ARCH_SI_PREAMBLE_SIZE` = 4*sizeof(int)) and not on 32-bit:

| | si_code | si_addr |
| --- | --- | --- |
| x86-64, aarch64 | 8 | **16** — measured (offsetof, and the $DEAD0000 assert) |
| i386, arm32, riscv32 | 8 | **12** — expected; MEASURE before trusting |

The 12 is from the asm-generic definition, not from a probe on this box (no
cross toolchains and no 32-bit headers installed). It is cheap to confirm once
SA_SIGINFO is on: the existing test faults on `$DEAD0000` and asserts si_addr
equals it, so a wrong offset shows up immediately under
`tools/run_target.sh <arch>`.

### Per target

- **aarch64 — easiest, no catches.** No SA_RESTORER (the kernel supplies the
  trampoline), so it is purely: add SA_SIGINFO to the flags word, and park
  x1 (siginfo*) / x2 (ucontext*) at the top of dispatch. si_addr @16.

- **riscv32 — same shape as aarch64.** No restorer; flags live at offset 4 in
  its ILP32 `struct sigaction`. Park a1/a2. si_addr @12.

- **arm32 — one real catch.** Handler args r0/r1/r2, si_addr @12, *and the
  restorer MUST flip from **sigreturn (119)** to **rt_sigreturn (173)***. ARM
  picks the signal FRAME SHAPE by SA_SIGINFO, not by which syscall installed
  the handler, so the moment the flag is set the old restorer is restoring a
  plain `struct sigframe` as if it were an rt frame — garbage context,
  pc=sp=lr=0, instant SIGSEGV (observed at b371). The existing code comment
  already says "(If SA_SIGINFO is ever set here, this MUST become 173.)"

- **i386 — TWO coupled changes, the riskiest.** Same 119 -> 173 flip as arm32,
  **plus the leading `pop eax` in the restorer must go.** That pop exists
  because `sys_sigreturn` recovers the frame at `sp - 8` while the plain
  frame's `ret` leaves esp at frame+4; the rt frame + `sys_rt_sigreturn` do not
  have that skew (glibc's i386 restorers differ in exactly this way — the
  non-rt one opens with `popl %eax`, the rt one does not). Get one of the two
  right and not the other and the context is garbage.
  Also note i386's handler arguments arrive **on the stack**, not in registers:
  with the rt frame, `[esp]` = pretcode, `[esp+4]` = sig, `[esp+8]` = siginfo*,
  `[esp+12]` = ucontext*. si_addr @12.

- **xtensa / ESP — N/A, and should stay refused.** FreeRTOS is not a Unix;
  there is no signal runtime there at all (`EmitSignalRuntime*` has no xtensa
  sibling), which is the same reason 33 PAL entry points are refused under IDF.

### One cross-cutting decision to make first

`__pxxSigCode` is typed **tyInt64** today (si_code is a signed 32-bit field and
the x86-64 stub sign-extends into an 8-byte slot). On the ILP32 targets an
Int64 is a register PAIR, so their stubs must write BOTH words — the value and
its sign word — or the slot reads as a huge positive number for the negative
SI_* codes. The alternative is retyping the intrinsic to **tyInteger** (32-bit,
signed) which is the field's real width and sidesteps the pair entirely; that
is a small change now and a breaking one later, so decide it before the first
32-bit target lands rather than after.

### Verification, per target

`tools/run_target.sh <arch> /tmp/<bin>` (qemu-arm / qemu-aarch64 / qemu-i386 /
qemu-riscv32 are all present on this box). `test/test_signal_siginfo.pas` is
already arch-independent — its si_addr assert against `$DEAD0000` is precisely
the offset canary, and its SI_TKILL half is the sign canary. Wire a per-arch
copy into each `test-<arch>` target the way the b371 signal tests already are.
