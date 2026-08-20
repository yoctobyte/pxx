---
track: A
prio: 55
type: feature
blocked-by: []
owner: ""
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

1. **SA_SIGINFO + ucontext.** *(DONE on all five hosted targets 2026-08-13 —
   flag set, si_code/si_addr/ucontext* readable, and the saved PC rewritable via
   `__pxxSigPCPtr`, so a hardware fault reaches a Pascal `except`. Nothing
   remains in item 1; items 2-5 keep this ticket open.)*
   Handler sees `siginfo_t` + register state
   (`ucontext_t`). This is the load-bearing piece for turning a fault into a
   *catchable* Pascal raise: modify ucontext RIP/PC to point at a raise stub
   before returning. Consumers: div-zero unification
   ([[decide-int-div-zero-behavior-unification]],
   [[bug-integer-div-zero-sigfpe-uncatchable]]), the float-exception-mask trap
   path ([[feature-float-exception-mask-control]]), and SIGSEGV/SIGBUS
   diagnostics ("fault at $ADDR in proc X").
   - **LANDMINE from b371, now DEFUSED (2026-08-13) — and it must stay that
     way:** arm32 and i386 pick the signal-frame shape by SA_SIGINFO, NOT by
     which sigaction syscall installed the handler, so their restorers flipped
     from **sigreturn (119)** to **rt_sigreturn (173)** in the same change that
     set the flag (i386 also dropped its leading `pop eax`). Those constants are
     now coupled to the flags word: never change one without the other, or the
     kernel restores a garbage context (pc=sp=lr=0 -> instant SIGSEGV).
     aarch64/riscv32 use the kernel vdso path either way and have no restorer.

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

## Progress — slice 2 landed (SA_SIGINFO on the remaining four targets), 2026-08-13

The rest of item 1's ACCESS half. aarch64, riscv32, arm32 and i386 now install
with SA_SIGINFO and park si_code / si_addr / ucontext* exactly as x86-64 does,
so `__pxxSigCode` / `__pxxSigAddr` / `__pxxSigContext` answer on every hosted
Linux target; only xtensa/ESP still refuses, deliberately (no signal runtime
there at all). Items 2-5 are untouched and this ticket stays open for them,
plus the PC rewrite.

The survey above was accurate and is left standing as the record; what it could
not know is below.

### The cross-cutting decision: `__pxxSigCode` is now `tyInteger`

Retyped from Int64 before the first 32-bit target landed, as the survey asked.
si_code's real width IS a signed 32-bit int; the deciding fact is that every
backend's `IR_EXC_STORE` moves **exactly one machine word**, so on ILP32 an
Int64 slot would have forced each 32-bit stub to synthesize a sign word into
the slot's upper half — four copies of a hazard whose failure mode is a huge
positive number for the negative SI_* codes. Typing it at the field's true
width removes the pair from all six backends at once. x86-64's stub still
sign-extends into its 8-byte slot, so the slot stays self-consistent for
anything that later reads it wide.

### si_addr on ILP32 is 12 — MEASURED now, not assumed

The survey's 12 came from the asm-generic definition, with a note to confirm
it. Confirmed on all three ILP32 targets: the test faults on `$DEAD0000` and
asserts si_addr equals it, and it does. (16 would have read the union's second
word and printed nonsense.)

### The b371 restorer landmine, defused

arm32: `mov r7, #119` -> `#173`. i386: `mov eax, 119` -> `173` **and** the
leading `pop eax` deleted — the two coupled changes the survey warned about,
both required, and the proof they landed is not the new test but the OLD one:
`test_signal_handler_callback_b336` still prints "resumed after handler" on
both targets, which is only possible if the restorer unwound the rt frame the
flag switched the kernel to. Comments at all three sites now say the flag and
the restorer constant are one change.

### Cost in the backends, again: zero

Nothing outside the four `EmitSignalRuntime*` stubs and the parser's guard
changed — no new IR op, no new AST node, no backend dispatch. The design signal
from slice 1 held: routing the three reads through `IRExcStoreSlot` means a new
target costs only its own stub.

### The test is arch-independent NOW

It was described as such but wasn't quite: its two raw syscall numbers (gettid
186, tkill 200) were x86-64's. They now sit behind `{$ifdef CPU*}` — 178/130 on
the asm-generic targets (aarch64, riscv32), 224/238 on arm32/i386. Wired into
`test-aarch64`, `test-riscv32`, `test-arm32` and `test-i386` beside the b371
signal tests.

### What is left of item 1

Only the PC rewrite: the ucontext pointer is parked on five targets and nothing
rewrites the saved PC yet, which is what
[[bug-integer-div-zero-sigfpe-uncatchable]] and
[[decide-int-div-zero-behavior-unification]] need. That work is now
five-targets-wide by default, and each target's saved-PC offset inside its
`ucontext_t` is per-arch — the one piece of per-target knowledge this slice did
NOT need and therefore did not establish.

Also worth noting for [[feature-float-exception-mask-control]]: its
`blocked-by` on "x86-64 only" is gone — `__pxxSigCode` now answers everywhere
it could.


## Progress — slice 3 landed (PC rewrite: a fault reaches a Pascal `except`), 2026-08-13

**Item 1 is now DONE on all five hosted targets.** Items 2-5 (threadsafe masks,
sigaltstack, FPC-compat `Signal()`, SIGPIPE policy) are untouched and keep this
ticket open.

### `__pxxSigPCPtr` — one intrinsic, a POINTER, not a read/write pair

It returns the ADDRESS of the saved program counter inside the parked ucontext.
Handing back the slot address rather than adding `__pxxSigPC` + `__pxxSetSigPC`
means reading (`PPtrUInt(__pxxSigPCPtr)^`) and rewriting
(`PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Handler)`) are both ordinary Pascal, and
the compiler owns exactly ONE fact: the per-arch offset. It also sidestepped
needing a statement-position intrinsic, which the expression-only `__pxxSig*`
family has no hook for.

Same guard as its three siblings: refused on xtensa and under `--no-signals`.
Meaningful only while a handler runs (ctx is nil otherwise) — the same
caller-must-know contract as si_addr being a pid for a kill()-delivered signal.

### The offsets, MEASURED — and the probe worth reusing

| target | offset | independently predicted by |
| --- | --- | --- |
| x86-64 | 168 | `uc_mcontext(40) + gregs[REG_RIP=16]*8` |
| aarch64 | 440 | `uc_mcontext(176) + fault_address + regs[31] + sp` |
| arm32 | 92 | `uc_mcontext(20) + arm_pc(72)` |
| i386 | 76 | `uc_mcontext(20) + gregs[REG_EIP=14]*4` |
| riscv32 | 160 | `uc_mcontext(160) + sc_regs.pc`, its first field |

The measurement technique generalises to any other ucontext field worth
reaching. Fault TWICE at the same sentinel address — once by WRITING it, once by
CALLING it — and dump every ucontext word equal to it. A word that matches in
both runs is a fault-address field; the word that matches only on the jump is
the saved PC. That separated the PC from three decoys per target (a general
register holding the call target, `cr2`/`fault_address`, and the FP-state
mirror). Both sources agree on all five, which is the second-source check
`devdocs/dev/debugging-playbook.md` asks for before writing a conclusion down.

### Why a raise from a kernel-resumed context is legal here

The exception runtime unwinds through its own **shadow stack** — `BSS_EXC_TOP`,
a chain of setjmp buffers — not through the hardware call stack. `ExcRaiseAddr`
loads that chain and longjmps, restoring SP from the buffer, so it does not care
that the kernel resumed us at an arbitrary PC with the faulting frame's SP. Had
the unwinder been frame-pointer- or DWARF-based this slice would have been a far
bigger job.

The redirect target must never RETURN, though: it is entered with a link
register full of pre-fault garbage. Raise or Halt.

### Cost in the backends: still zero

`__pxxSigPCPtr` lowers to the existing slot load plus an `IR_BINOP` pointer add
against an `IR_CONST_INT`. No new IR op, no new AST node, no backend edit — the
same invariant slices 1 and 2 held. `UContextPCOffset` in `ir.inc` is the only
new per-arch knowledge in the compiler.

### What this does NOT decide

WHICH exception a fault should raise. The new test raises a bare ordinal
(`raise 42`), which needs no exception class and no sysutils, precisely so the
mechanism could land without pre-empting
[[decide-int-div-zero-behavior-unification]] — still open on where a builtin
exception class should live. That decision now has a working mechanism under it
rather than a design sketch; whoever resolves it writes RTL, not codegen.

Test `test/test_signal_pc_rewrite.pas`, wired into all five suites: it faults by
CALLING $DEAD0000 (so the saved PC must BE that address — an exact check of the
offset), rewrites the PC to a raising proc, and the fault is caught by the
try/except the faulting code was already inside, with execution continuing after.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted.** Measured rather than read: item 1 is indeed
done, and the *consumer* path it was for is not. A `Low(Int64) div -1` inside a
`try … except on E: Exception` still core-dumps with SIGFPE (exit 136) instead
of reaching the handler, so nothing here has landed incidentally. Items 2-5
stand as written.

## Progress — item 3 landed (x86-64 sigaltstack + SA_ONSTACK), 2026-08-20

**Item 3 only.** Items 2, 4 and 5, and the other four targets, are untouched;
this ticket stays open for them.

### The gap, measured before writing anything

A stack-overflow SIGSEGV was **unhandleable**, and not by a subtlety: install a
hook with `SetSignalHandler(11, ...)`, recurse until the guard page, and the
program dies with **exit 139 and the hook never entered**. It cannot run,
because the fault happens precisely when there is no stack left — pushing a
signal frame onto the faulting stack faults again, and the kernel kills the
process outright.

Oracle: the same program in C (gcc, `sigaltstack` + `SA_ONSTACK | SA_SIGINFO`)
prints `code=1 depth=7936` and exits 0. pxx now prints `code=1 depth=8056` and
exits 0 — the depths differ because the frames differ, which is why the test
does not assert one.

### What landed

- **`sigaltstack(2)` (syscall 131) at the top of the install stub**, pointing at
  a `SIG_ALTSTACK_SIZE` (32 KiB) BSS buffer, and **`SA_ONSTACK`** added to the
  flags word: `$14000004` -> `$1C000004`. Neither half works alone — the flag
  without a registered stack is ignored, and the stack without the flag is never
  used.
- Re-registering on every install rather than once behind a flag: `sigaltstack`
  is idempotent with the same values, and one syscall per `SetSignalHandler`
  call is cheaper than a "have we done this yet" bit and the bug it eventually
  grows.
- `rdi` carries the signal number into the `rt_sigaction` below, so it is parked
  in `r8` across the syscall rather than reloaded.

### Storage placement — the BSS_IO_OWNER lesson, applied on purpose

The buffer and its 24-byte `stack_t` are allocated **inside `EmitSignalRuntime`**,
next to the only code that reads them — not in the Pascal driver where the other
`BSS_SIG_*` slots live. That is the rule
`EmitIoLockStubsForTarget` had to learn the hard way: storage allocated in the
Pascal driver is storage every *other* frontend leaves at 0, which is to say
aliased onto offset 0. `BSS_IO_OWNER` and `BSS_IO_DEPTH` became the same eight
bytes that way and `--threadsafe` hung on every NilPy program.

(The pre-existing `BSS_SIG_*` slots still sit in the Pascal driver. Not touched
here — that is exactly [[bug-a-only-the-pascal-driver-emits-the-signal-runtime]],
whose scope is "make every frontend call the runtime", and widening this slice
into it would tangle two changes. The new slots simply do not add to the debt.)

### x86-64 only, and the b371 landmine is still untouched

i386 and arm32 pick the signal FRAME SHAPE by SA_SIGINFO rather than by which
syscall installed the handler, and their restorers still call `sigreturn (119)`.
Nothing here touches their install sites — same reason the SA_SIGINFO slice was
x86-64-only. Whoever does those targets must flip them to `rt_sigreturn (173)`
in the same change.

### Test

`test/test_signal_altstack.pas`, wired into `make test`. **The load-bearing
assertion is not that the program survived** — surviving shows the handler ran,
not *where*. The handler compares its own frame address against the faulting
address: on the alt stack (a BSS buffer, ~4 MB) versus the faulting stack
(~140 TB) they are hundreds of megabytes apart, so `gap > $10000000` proves
sigaltstack took effect rather than the overflow having happened to leave a
usable slack page. Recursion depth is deliberately not printed — it depends on
`RLIMIT_STACK` and frame layout, the classic source of a flapping test.

Bites: the pinned binary dies with exit 139 on it.

### And what it immediately exposed

With a handler finally able to RUN on a stack overflow, the obvious next step —
point the ucontext PC at a raise stub, as item 1's machinery already allows —
**loops forever**: the resumed stub inherits the exhausted SP and re-faults at
the identical address. Measured and filed as
[[bug-a-stack-overflow-fault-to-raise-loops-forever-without-an-sp-reset]].
It is a sharp edge on a newly reachable capability, not a regression; the
ordinary hook-and-return case exits cleanly. Whoever takes item 1 further should
read it first — fault-to-raise needs an SP reset for this one signal.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint, converged after 2 rounds) +
`tools/gate.sh quick` GREEN, and all four existing signal tests re-checked by
hand against their Makefile assertions (`test_signal_handlers`,
`test_signal_siginfo`, `test_signal_pc_rewrite`,
`test_signal_handler_callback_b336`) — the hook ABI is unchanged, which is what
makes this additive.
