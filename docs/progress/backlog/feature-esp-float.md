# ESP float wiring (xtensa + riscv32 float value model)

- **Type:** feature (cross codegen depth, ESP targets)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

xtensa + riscv32 have **no float value model at all** — even `a:=1.5; b:=a+2.0`
errors `unsupported node in IR codegen`. This is why float function returns
couldn't be enabled there in [[feature-cross-float-returns]] (Linux targets done).

## OPEN DECISION — what does `Real` map to on no-FPU targets?

Per FPC docs: "`real` maps to the **double** type on processors which support
floating point operations, while it maps to the **single** type on processors
which do not support floating point operations in hardware." So in FPC `Real` is
FPU-presence-dependent. **PXX currently deviates** — `Real` is hardwired to
`tyDouble` on every target (parser.inc:6513,6552), no-FPU included.

Two coherent options; pick before scoping [[feature-softfloat-lib]]:

- **(A) FPC-faithful — no-FPU `Real` = Single.** Common float code on riscv lowers
  to soft-**single** (cheaper, 32-bit; the precision FPC gives there). Explicit
  `Double` still needs soft-double, but it's the rare path. Pro: matches FPC,
  cheaper hot path. Con: same `Real` source yields different precision per target
  (FPC already accepts this); a small parser change to make `Real` target-aware.
- **(B) Keep `Real`=Double everywhere.** Numeric portability (identical precision
  all targets) over FPC-fidelity. soft-float lib collapses to double-only; single
  (rare, explicit) widens to soft-double. Simpler lib, slower/heavier no-FPU
  arithmetic, documented FPC-deviation.

Recommendation: **(A)** — it's both FPC-correct and the cheaper MVP, and PXX
already forks numeric width on the integer side (NativeInt/PtrInt). The only real
cost is a target-aware `Real` mapping in the parser.

## Design (under option A)

`Single` is still storage-only with widen-for-math **on double-capable targets**
(x86-64/i386/aarch64/arm32 — unchanged, that's the right model there). On no-FPU
riscv, `Real`→Single means the common path is native soft-single; explicit Double
is soft-double.

| target                     | hot path (`Real`) | double (explicit) | single |
|----------------------------|-------------------|-------------------|--------|
| riscv32 (ESP32-C3, no FPU) | soft-single       | soft-double       | soft-single |
| xtensa (ESP32 / S3)        | soft-double*      | soft-double       | widen→soft-double (baseline) |

*xtensa has hardware FP, so by the FPC rule `Real`=Double there.

### Optional optimization (xtensa only, defer)

xtensa has a hardware **single-precision** FPU. Pure-single code could run on it
instead of widening to soft-double — a speed win for single-heavy ESP workloads.
OPTIMIZATION, not correctness; do it after the soft baseline works. Not on the
critical path.

## Dependencies

- [[feature-softfloat-lib]] — the soft-double kernels + s<->d / i<->d conversions
  this wiring calls. (No first-class-single ticket: storage-only-widen is the
  model, so there's nothing to make "first class".)

## Approach (per target, after the lib lands)

1. Value model: carry a Double as raw bits in a core-register pair (riscv a0:a1,
   xtensa a-pair), mirroring arm32's d0->r0:r1 spill.
2. Lower the float IR nodes (`ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`):
   literal, IR_LOAD_SYM / STORE (8-byte slot moves), binops -> soft-double helper
   calls, intrinsics, single-load = soft-widen to double, single-store = soft-
   narrow, then params + returns.
3. Relax the EmitProcEpilog float guards last (symtab.inc ~3713 xtensa /
   ~3753 riscv32) — only once arithmetic + params are correct.
4. Add float tests to the ESP/cross suites; QEMU output-equality vs the x86-64
   oracle (ESP self-host is not a goal — device RAM too small).

## Notes

- Order within: literal+load/store+`dcmp` first (unblocks comparisons/branches),
  then add/sub, mul/div, conversions, params/returns.
- error-not-miscompile: leave each unimplemented piece erroring; never ship silent
  garbage.
- The float-return/param recipe from [[feature-cross-float-returns]] applies
  verbatim once arithmetic exists.
