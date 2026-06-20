# Cross-target float function results

- **Type:** feature (cross codegen depth)
- **Status:** working
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

Float-typed function results (`function F: Double` / `Single` / `Extended`)
**error on every cross target**:

```
target <arch>: only ordinal/pointer/string function results supported yet
```

(symtab.inc EmitProcEpilog, one guard per target: i386 ~3497, arm32 ~3613,
aarch64 ~3679, xtensa ~3710, riscv32 ~3750.)

This is the last broad float gap on cross targets. `feature-cross-float-variant`
(done) already landed float arithmetic, mixed int/float, comparisons, intrinsics
(Trunc/Round/Frac/Int), formatting, params, and consts; and int→float **assign**
already works cross (e.g. aarch64 ir_codegen_aarch64.inc ~855 does `scvtf`).
Only the function-**return** path was never enabled.

## Approach

The internal value model carries a float as its raw double-bits in the
**integer return register** (x0 / r0 / eax(:edx) / a2 / a0) — the same register
EmitLoadVar* already targets for ordinals. So enabling float returns is mostly
relaxing the per-target guard to allow `TypeIsFloat`, then confirming the result
load writes the full width into the return reg (8 bytes for Double; Single is
widened to double-bits by EmitLoadVar* already). 64-bit-in-2-regs targets (i386
eax:edx, arm32 r0:r1) need the Int64-style two-word load for an 8-byte Double.

Internal calls only — external C float returns have their own ABI path
(test_extern_c_float, already green).

## Plan / status
- [x] **aarch64 — DONE.** Value model carries floats as bits in x0 (= the return
  reg); guard relaxed to allow `TypeIsFloat`, EmitLoadVarA64 already loads the
  Double's 8 bytes / widens a Single into x0. Float PARAMS already worked on
  aarch64. test/test_cross_float_return.pas wired into the aarch64 cross suite.
- [x] **arm32 — DONE.** Both params + return. Return: Double bits in r0:r1
  (EmitLoadVar64Arm32), caller moves r0:r1->d0 (mirrors the external-call path);
  Single bits in r0 -> s0->d0. Params: by-value Double counted/spilled as 2 words
  in the prologue (parser.inc, alongside Int64); caller evaluates the arg to d0,
  `vmov r0,r1,d0`, pushes 2 words (Single: vcvt s0,d0 -> r0, 1 word). Guard
  relaxed for TypeIsFloat. test wired into test-arm32; make test byte-identical
  (no reseed).
- [x] **i386 — DONE.** Float PARAMS were already wired (prologue copies the
  8-byte Double slot, caller pushes the spilled xmm0 double). Only the RETURN was
  missing: guard relaxed for TypeIsFloat; the existing sz=8 result-load returns a
  Double in eax:edx (Single in eax); caller moves eax:edx -> xmm0 (Single: movd +
  cvtss2sd) for the SSE value model. test wired into test-i386; make test
  byte-identical (no reseed).
- [ ] xtensa — needs param + return (errors cleanly today).
- [ ] riscv32 — needs param + return (errors cleanly today).
- [ ] gate: make test + cross-bootstrap + cross suites green

## KEY FINDING (2026-06-20)

Float function results were never enabled, which ALSO meant float PARAMETERS were
never exercised on internal cross calls — any float-param function hit the return
guard first and errored. So on arm32/i386/xtensa/riscv the work is **both**:
1. caller: pass a float arg in the target's call-arg registers (e.g. arm32 d0 →
   r0:r1 for Double / r0 for Single; the prologue word-spill at parser.inc ~7987
   may already reconstruct the slot correctly — verify);
2. callee: return the float in the convention the caller consumes.
aarch64 needed neither (bits-in-x0 = both arg and return reg already). Each
remaining target is its own ABI slice; do one at a time, QEMU-tested, then add it
to that target's cross suite.

## Next-session prompt (continue: float returns on all remaining targets)

> Track A. Continue `feature-cross-float-returns` (docs/progress/working/).
> aarch64 is DONE (commit f7feaad). Finish **arm32, i386, xtensa, riscv32** — each
> needs float-typed function **params AND returns** on internal calls (params were
> never exercised because the return guard blocked every float-param fn). Do ONE
> target at a time, QEMU-tested, commit per target.
>
> Per-target recipe:
> 1. Reproduce: `function Half(x:Double):Double; begin Half:=x/2.0 end;` +
>    `function NoParam:Double; begin NoParam:=3.14 end;` Compile `--target=<t>`,
>    run via `tools/run_target.sh <t>`. NoParam tests return-only; Half tests
>    params. (On arm32 today NoParam works, Half gives garbage.)
> 2. Learn the target's float value model: how IR_LOAD_SYM loads a float
>    (ir_codegen_<t>.inc) and which reg the value model uses (arm32=d0 VFP;
>    i386=? check x87/SSE; xtensa/riscv=? likely soft-float core regs). The
>    return + arg conventions must match what the CALLER consumes.
> 3. Callee epilogue (symtab.inc EmitProcEpilog, per-target block): relax the
>    guard to allow `TypeIsFloat`; load the float result into the convention reg
>    (arm32 Double->d0 worked; i386 Double=eax:edx via the existing sz=8 path;
>    map each).
> 4. Caller arg-pass (ir_codegen_<t>.inc, the generic internal IR_CALL arg loop —
>    past the special cases): place each float arg in the call-arg reg(s)
>    (arm32: d0 -> r0:r1 Double / d0->s0->r0 Single, push as words). The prologue
>    word-spill (parser.inc ~7987) likely already reconstructs an 8-byte Double
>    param slot from 2 words — VERIFY before adding code; IR_LOAD_SYM then reads
>    the slot via the float load.
> 5. Add the target's line to test/test_cross_float_return.pas's cross-suite entry
>    (Makefile, mirror the aarch64 block at the test_cross_float entry).
> 6. Gate per target: `make test` (x86-64 untouched -> should stay byte-identical,
>    NO reseed; if a shared path changed and fixedpoint breaks, it's a reseed —
>    `make bootstrap` then retest, do NOT call it non-determinism), then
>    `make test-<t>` (or cross-bootstrap if shared code touched). Commit.
> Rule: if a target's params can't be made correct yet, leave that target ERRORING
> (don't ship silent garbage). Single-literal->Single-param narrowing is a
> SEPARATE ticket (feature-double-to-single-narrowing) — don't fold it in; keep
> the test Double-only unless you also do that ticket.
> Landmines: shared checkout w/ Track B — `git commit -- <paths>`, verify
> `git show --stat`; never push without the user's OK.

## Log
- 2026-06-20 — Opened from the result-in-loop / int-to-float arc, which found the
  guard. Scoped: value model already float-bits-in-int-reg, so this is guard
  relaxation + result-load width per target, not new float infrastructure.
- 2026-06-20 — aarch64 slice landed (f7feaad). Found float PARAMS also unwired on
  non-aarch64 targets; documented the per-target recipe + next-session prompt
  above.
