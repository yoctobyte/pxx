---
track: B
prio: 45
type: feature
blocked-by: []
summary: "FPC's Math-unit float-exception surface — TFPUException / TFPUExceptionMask / GetExceptionMask / SetExceptionMask — as a set<->bitmask wrapper over the __pxxGetFPUMask / __pxxSetFPUMask intrinsics that landed 2026-08-13. Wrapper only: the mechanism, the target refusals and the trap semantics are all already decided in the compiler."
status: done
owner: track-b-bughunt
---

# FPC-compatible Get/SetExceptionMask in lib/rtl/math.pas

- **Type:** feature (library / FPC compat) — **Track B** (`lib/rtl/math.pas`)
- **Opened:** 2026-08-13, split out of [[feature-float-exception-mask-control]]
  when that ticket's slice 1 landed the intrinsics.

## What to write

```pascal
type
  TFPUException = (exInvalidOp, exDenormalized, exZeroDivide,
                   exOverflow, exUnderflow, exPrecision);
  TFPUExceptionMask = set of TFPUException;

function GetExceptionMask: TFPUExceptionMask;
function SetExceptionMask(const m: TFPUExceptionMask): TFPUExceptionMask;
```

`__pxxGetFPUMask` / `__pxxSetFPUMask(m)` already trade in a **6-bit integer in
exactly this enum's order**, with 1 = masked — the compiler chose that encoding
so this wrapper is a set<->bitmask conversion and nothing else. `SetExceptionMask`
returns the previous mask (FPC returns the *new* one; check FPC's actual
signature before matching it — its Math unit returns the mask that ended up in
effect).

FPC's enum has the same six members in the same order, which is not a
coincidence: it is x87/MXCSR's mask-bit order.

## Constraints

- **Needs the intrinsics pinned first.** `lib/**` builds with `$(PXX_STABLE)`,
  so this cannot land until a pin carries `__pxxGetFPUMask`/`__pxxSetFPUMask`
  (`bug`-shaped failure otherwise: `lib-test` goes red and `gate.sh quick`
  cannot see why).
- **x86-64 only.** The intrinsics are a compile-time Error on every other
  target (i386 not ported; aarch64/arm32/riscv32 have no architecturally
  guaranteed trap enable). So the whole unit section must sit behind
  `{$ifdef CPUX86_64}` or the RTL stops building for the cross targets — and
  the non-x86-64 arm must **refuse**, not silently answer "all masked", for the
  reason the compiler refuses.
- **Do not change the default.** pxx stays quiet IEEE (user decision,
  2026-07-02): this API lets a program opt in, it does not unmask anything at
  startup. `test/test_float_exception_mask.pas` pins that.

## Also worth knowing

A handler for the resulting SIGFPE must **not** re-mask and return — sigreturn
restores the FP state from the ucontext and the instruction re-traps forever.
Recover through `__pxxSigPCPtr` or halt. The parent ticket records the measured
si_code per cause (FLTDIV 3 / FLTOVF 4 / FLTUND 5 / FLTRES 6 / FLTINV 7).

## Gate

`make lib-test` green + a demo/test that round-trips a mask and shows the
default is untouched.

## Resolution (2026-08-15)

Landed in `lib/rtl/math.pas` behind `{$ifdef CPUX86_64}` as the ticket
specified, with `test/fpu_exception_mask_x64.pas` (15 rows) wired into
`lib-test`.

**The blocker was already clear.** The pinned stable carries
`__pxxGetFPUMask`/`__pxxSetFPUMask` — checked before writing a line
(`__pxxGetFPUMask` answers 63, i.e. all six masked, which is also the quiet-IEEE
default this ticket must not change).

### Two things the ticket predicted wrongly, both measured

- **`SetExceptionMask` returns the PREVIOUS mask, not the new one.** The ticket
  guessed "FPC returns the mask that ended up in effect"; an FPC 3.2.2 probe
  says otherwise — `SetExceptionMask(x)` hands back what was in force before,
  which is what makes save/restore a single expression. Matched.
- **`__pxxSetFPUMask` is an EXPRESSION, not a statement.** It already returns
  the previous mask, so the wrapper is one call rather than a read-then-write
  pair. Calling it in statement position is an `undefined variable` error, which
  is how this was found.

### The non-x86-64 arm refuses by being ABSENT

No stub. The intrinsics are a compile-time Error on every other target, so a
non-x86-64 build fails on the *call site* — the same refusal the compiler makes,
and the same shape `lib/rtl/coroutine.pas` already uses. A stub answering "all
masked" would be a lie the caller cannot detect, which is exactly what the
ticket said to avoid.

### The test is named outside the lib-test glob, deliberately

`tools/lib_cross_sweep.sh` builds every lib test source for i386, arm32,
aarch64 and riscv32. This API cannot build on any of them **by design**, so a
`lib_`-named test would read as four sweep failures instead of as a refusal.
Hence `test/fpu_exception_mask_x64.pas`, wired into `lib-test` directly.

Not covered here: that clearing a bit actually traps. It does, but a test whose
success condition is a fatal signal belongs in the compiler suite, where
`test/test_float_exception_mask.pas` already carries it.

The default is untouched — `default-all-masked` pins that, and FPC's differing
default (invalid/zero-divide/overflow unmasked there) is left alone on purpose.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
