---
track: A
prio: 60
type: feature
blocked-by: []
owner: claude-A-C-N
---

# Float exception mask control (SetExceptionMask-style, FPC emulation opt-in)

- **Type:** feature (runtime / math) — Track A
- **Status:** working
- **Opened:** 2026-07-02, from the math-error design discussion with the user.

## Decision already made (user, 2026-07-02)

- **Default stays quiet IEEE**: `1.0/0.0 = +inf`, overflow → inf, invalid →
  NaN, silently propagated. Rationale (user): real-world measurement/streaming
  data with out-of-bounds inputs is better served by inf/NaN propagation
  through complex math than by aborting mid-computation; FPC's
  unmask-by-default is the wrong default for that domain.
- **FPC emulation is opt-in**: we want to be *able* to emulate FPC closely
  (FPC unmasks x87 CW / SSE MXCSR at startup, so float div-zero = RE 208 /
  EZeroDivide, overflow = RE 205, invalid = RE 207), but behind an explicit
  runtime/compile opt-in, not the default.

## Scope

- `GetExceptionMask` / `SetExceptionMask([exZeroDivide, exOverflow, ...])`
  API (FPC Math-unit-compatible surface) manipulating MXCSR (x86-64) /
  FPCR (aarch64) / per-target equivalent.
- Unmasked exception → hardware SIGFPE → signal handler (the blocker) decodes
  siginfo `si_code` (FPE_FLTDIV/FPE_FLTOVF/FPE_FLTUND/FPE_FLTINV) → FPC-style
  runtime error 205/206/207/208, hook-upgradable to a raised exception like
  the integer path's PXXDivZeroHook.
- Possibly a `--fpc-float-errors` CLI flag / directive that unmasks at entry
  (the "emulate FPC closely" switch).
- Note: pre-instruction value checks are NOT a substitute here (user + design
  discussion): a zero-divisor test misses overflow (`1e308/1e-308`) and
  denormal cases; the mask/trap mechanism is the only honest implementation.

## Acceptance

Default behavior unchanged (quiet inf/NaN — add a pin test for that too);
with the mask cleared, float div-zero/overflow/invalid produce the documented
runtime errors; mask round-trips via Get/SetExceptionMask; x86-64 first.

## BLOCKED on SA_SIGINFO — measured 2026-08-13

Recording the dependency the ticket did not have. The acceptance criterion is
that an unmasked float exception produces the *documented* runtime error —
205 (overflow) / 206 / 207 (invalid) / 208 (div-zero), i.e. **distinguished by
cause**. The handler must therefore learn WHICH exception fired, and today it
cannot:

- the x86-64 signal runtime (`EmitSignalRuntime`, ir_codegen.inc) installs the
  dispatch stub with the **plain** handler ABI — `edi` = signal number and
  nothing else. No `SA_SIGINFO`, so no `siginfo_t`, so no `si_code`.
- **the MXCSR status flags are NOT an alternative.** That was the promising
  route (read the sticky IE/ZE/OE bits in the handler and skip siginfo
  entirely), so it was measured rather than assumed:

  ```
  1.0/0.0     si_code=FLTDIV   mxcsr_flags=0x00
  0.0/0.0     si_code=FLTINV   mxcsr_flags=0x00
  1e308*10    si_code=FLTOVF   mxcsr_flags=0x00
  ```

  Linux hands the signal handler a CLEAN FP state, so the status flags read
  0x00 no matter which exception trapped. `si_code` is the only carrier.
  (Same probe also shows why a handler that `siglongjmp`s out never re-traps:
  skipping `sigreturn` leaves the handler's own masked MXCSR installed.)

So `feature-signal-siginfo-ucontext` item 1 (SA_SIGINFO + ucontext) is a hard
prerequisite, not a nice-to-have. That ticket already lists this one as a
consumer; the edge is now recorded in both directions, so prio 60 propagates
down to it.

**What is NOT blocked**, if this is picked up before siginfo lands: the
`Get`/`SetExceptionMask` API itself (MXCSR on x86-64 / FPCR on aarch64) and
the "default stays quiet IEEE" pin test are self-contained. Deliberately NOT
landed as a half-slice — an exception-mask API whose unmasked path produces an
undifferentiated crash is the consolation microfix
`devdocs/dev/root-cause-over-microfix.md` warns about, and the mask is only
worth having once the trap means something.

**Un-blocking checklist (both switches):** when siginfo lands, move this file
OUT of `blocked/` *and* clear the `blocked-by:` line. Either one alone leaves it
invisible to `ready`/`next`.

**UNBLOCKED 2026-08-13** — both switches thrown (this file moved to `backlog/`,
`blocked-by:` emptied). The prerequisite is met and then some: SA_SIGINFO is set
and `si_code` readable via `__pxxSigCode` on ALL FIVE hosted Linux targets, not
just x86-64 (`feature-signal-siginfo-ucontext` slices 1 and 2). Note
`__pxxSigCode` is typed **Integer**, not Int64 — si_code's real width, retyped
so the ILP32 targets need no sign word.

That parent ticket stays OPEN, but for work this one does not need: the
fault-to-catchable-raise PC rewrite, threadsafe masks, sigaltstack, the
FPC-compat `Signal()` surface, SIGPIPE policy. Do not re-block on it.

## Progress — slice 1 landed: the MASK itself (x86-64), 2026-08-13

The mechanism half of this ticket. The default is unchanged and now PINNED by a
test; a program can unmask a cause and the SSE instruction traps SIGFPE with an
si_code that says which. The FPC-shaped `Get`/`SetExceptionMask` set surface and
the 205/206/207/208 mapping are NOT here — see "what is left" below.

### Two intrinsics, and SET returns the PREVIOUS mask

    m   := __pxxGetFPUMask;                        { 63 = all masked = default }
    old := __pxxSetFPUMask(m and not 4);           { unmask exZeroDivide }
    old := __pxxSetFPUMask(old);                   { restore }

The value is a 6-bit set in **FPC's TFPUException order** — bit 0 exInvalidOp,
1 exDenormalized, 2 exZeroDivide, 3 exOverflow, 4 exUnderflow, 5 exPrecision —
with 1 = masked. That order **is** MXCSR's mask bits 7..12 in order, so the
target-neutral encoding costs one shift and no table, and the RTL wrapper this
is waiting for is a set<->bitmask conversion and nothing else.

SET returning the old value is what keeps the family expression-only, so it
needs no statement-position hook — the same call `__pxxSigPCPtr` made by handing
back a pointer instead of adding a setter. The cost is that a caller must assign
the result (`old := __pxxSetFPUMask(...)`), which the wrapper hides.

### x86-64 only, and REFUSED elsewhere — with i386 told apart

Two different messages, because two different reasons:

- **i386**: not ported. It does its float arithmetic in SSE too, so MXCSR is the
  identical mechanism; what stops a copy-paste is its **x87 control word**,
  which the backend still uses for the Int64 conversions (`fisttp`/`fistp`) and
  which would have to move with the MXCSR word or the mask would be half true.
- **aarch64 / arm32 / riscv32**: the value could not be honest there. FPCR/FPSCR
  trap-enable bits are permitted to be RES0 and most implementations never trap,
  and RISC-V has **no trapping FP at all** — only sticky flags. Accepting the
  call and reporting a mask that does nothing is exactly the silent wrong answer
  this dialect refuses to invent (the ESP PAL's `PAL_ERR_UNSUPPORTED` call).

Guarded twice, in the parser and again in `IRLowerAST`, which is what keeps the
promise that no other backend ever sees `IR_FPU_MASK` — the same arrangement
`IR_MULHI` has for the 32-bit targets. Cost in the other five backends: zero.

### Measured: every cause reports itself, distinctly

`test/test_float_exception_mask.pas`, wired into `make test`:

| unmasked | operation | si_code |
| --- | --- | --- |
| exZeroDivide | `1.0/0.0` | 3 FPE_FLTDIV |
| exOverflow | `1e308*10` | 4 FPE_FLTOVF |
| exInvalidOp | `0.0/0.0` | 7 FPE_FLTINV |
| exUnderflow | `1e-300*1e-30` | 5 FPE_FLTUND |
| exPrecision | `1.0/3.0` | 6 FPE_FLTRES |

That table is the whole reason the siginfo prerequisite existed, and it is now
a fact rather than a plan: a 205/206/207/208 mapping is a `case` over that
column. The same test pins the default — `1/0 = +Inf`, `1e308*10 = Inf`,
`0/0 = Nan`, mask 63 before and after — so a future change that unmasks by
default turns `make test` red, which is what the user's 2026-07-02 decision
deserves.

### The trap-handler landmine: re-masking inside the handler does NOT let it return

The first cut of the test re-masked MXCSR in the handler and returned, expecting
the faulting instruction to retry quietly. **It hangs forever.** `sigreturn`
RESTORES the FP state from the ucontext, so the handler's `ldmxcsr` is discarded
and the instruction re-traps — the same "Linux hands the handler a clean FP
state" fact that made the MXCSR status flags useless as a cause carrier, seen
from the other side. Recovery goes through the saved PC (`__pxxSigPCPtr`),
exactly as it does for SIGSEGV, or the handler halts. Recorded here because the
retry route is the obvious one to try and it costs a hang to find out.

(Recovering by RETURNING would mean patching MXCSR inside the ucontext's
`fpstate`, a further per-arch offset nobody needs yet — the FPC behaviour being
emulated aborts, and the catchable route already works.)

### The operand is evaluated BEFORE the stmxcsr

`__pxxSetFPUMask(f(x))` — the argument is an arbitrary expression that may CALL,
and a call writes below rsp, straight through the red-zone word (`[rsp-8]`) the
saved MXCSR would have been sitting in. Emitting the operand first is a
one-line ordering fact with a silent wrong answer behind it.

### What is left of this ticket

1. **The FPC-compatible surface**: `TFPUException` / `TFPUExceptionMask` and
   `Get`/`SetExceptionMask` in `lib/rtl/math.pas` — a set<->bitmask wrapper over
   these two intrinsics and nothing more. That is a **Track B** file and needs
   the intrinsics PINNED first (lib builds with the pinned compiler), so it is
   filed separately rather than done here.
2. **`--fpc-float-errors`**: unmask at entry + a SIGFPE handler that maps
   si_code to runtime error 205/206/207/208. Pure Track A, self-contained now
   that the table above is measured.
3. **i386**, per the refusal message above.

## Progress — slice 2 landed: `--fpc-float-errors`, 2026-08-13

The opt-in from the 2026-07-02 decision, now real. The default is untouched
(and pinned by two tests); with the flag, pxx reports float faults the way FPC
does, **verified against FPC 3.x on this box rather than against a table**:

| | pxx `--fpc-float-errors` | FPC 3.x |
| --- | --- | --- |
| `1.0/0.0` | Runtime error 208, exit 208 | Runtime error 208 |
| `1e308*10` | Runtime error 205, exit 205 | Runtime error 205 |
| `0.0/0.0` | Runtime error 207, exit 207 | Runtime error 207 |
| `Low(Int64) div -1` | Runtime error 200, exit 200 | Runtime error 200 |

### What the flag does, in two pieces

At program entry, in this order: install a SIGFPE hook, then unmask. (The other
order has a window where a trap has no handler.) The unmask value is **FPC's
own default mask, measured** — `GetExceptionMask` under FPC answers
`{exDenormalized, exUnderflow, exPrecision}`, i.e. invalid / zero-divide /
overflow unmasked, which is bits 1|4|5 = 50 in this ticket's neutral encoding,
`$1900` in MXCSR position.

The hook is `EmitFpcFloatErrStub` — a decode chain over the parked si_code that
writes the message and `exit_group`s with the FPC number. Pure syscalls, no unit
dependency, exactly like the div-zero stub it sits beside.

### The integer FPE causes are decoded too, and that is not scope creep

SIGFPE carries `FPE_INTDIV` and `FPE_INTOVF` as well. Leaving them to fall
through would print a *float* message for an integer fault — a wrong answer the
flag introduced. So they map to 200 and 215, which is also why
`Low(Int64) div -1` now says something instead of dying uncatchably (see
[[bug-integer-div-zero-sigfpe-uncatchable]] — this does not close that ticket,
which wants a *catchable* raise, but it is the same fault reaching a diagnosis).
FPC agrees on that row too: 200, measured.

### An si_code the decoder does not know exits 255, saying so

`FPE_FLTRES` (inexact) has **no FPC runtime error** — FPC masks precision and
never faces the question. Picking a plausible 205/207 for it would be the
invented-answer failure this dialect refuses, so it and any unrecognised code
print a message that names the situation and exit 255, which is not an FPC code.
Reachable only if the program unmasked precision itself through
`__pxxSetFPUMask`.

### Refusals

`--fpc-float-errors` errors on a non-x86-64 target (no portable mask mechanism —
see slice 1) and errors with `--no-signals`, because the flag IS a signal hook
and silently doing half of it (unmask, no handler = a bare SIGFPE kill) would be
worse than not compiling.

### Test

`test/test_fpc_float_errors.pas`, wired into `make test` and run **five ways**:
the same source with the flag (no-trap exit 0, div 208, ovf 205, inv 207) and
WITHOUT it (`no trap, r= Inf`, exit 0). That last line is the one that fails if
anyone ever makes unmasking the default.

The user-facing CLI reference row is `docs/**` (Track D) and is filed as
[[docs-cli-fpc-float-errors-flag]].

### Still open in this ticket

- The FPC-compatible `Get`/`SetExceptionMask` **set** surface in
  `lib/rtl/math.pas` — Track B, needs a pin first:
  [[feature-b-fpc-exception-mask-api-in-math]].
- **i386**, per slice 1's refusal message (its x87 control word would have to
  move with MXCSR).
- Making the trap **catchable** (`try/except EZeroDivide`) rather than a print +
  exit. The mechanism exists — the handler can rewrite the PC to a raising proc
  (`__pxxSigPCPtr`, proven in `test/test_float_exception_mask.pas`) — but WHICH
  exception class and where it lives is still
  [[decide-int-div-zero-behavior-unification]], which is a Track U question, not
  an implementation one.
