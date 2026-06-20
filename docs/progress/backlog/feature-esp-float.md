# ESP float wiring (xtensa + riscv32 float value model)

- **Type:** feature (cross codegen depth, ESP targets)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

xtensa + riscv32 have **no float value model at all** — even `a:=1.5; b:=a+2.0`
errors `unsupported node in IR codegen`. This is why float function returns
couldn't be enabled there in [[feature-cross-float-returns]] (Linux targets done).

## RESOLVED MODEL — `Real` = the target's native float depth

PXX defines `Real` as **the widest float the target does natively** (a clean
generalization of FPC's with/without-coprocessor rule). Well-defined per target,
documented:

- `Single` = IEEE binary32, always 4-byte storage.
- `Double` = IEEE binary64, always 8-byte storage. **Available on every target**
  (soft where there's no hardware double — ESP keeps doubles).
- `Real` = alias to the native depth: Double on double-HW targets, Single on
  single-only / no-FPU targets.

This means the float arithmetic dispatch is:

| target                     | native (`Real`=) | Single math      | Double math |
|----------------------------|------------------|------------------|-------------|
| x86-64/i386/aarch64/arm32  | Double           | widen→Double (storage-only, current) | HW |
| xtensa (ESP32 / S3)        | **Single**       | **HW single FPU**| soft-double |
| riscv32 (ESP32-C3)         | **Single**       | soft-single      | soft-double |

Notes:
- Single stays storage-only/widen **only on double-native targets** (native single
  buys nothing there). On ESP, Single is first-class — HW on xtensa, soft-single on
  riscv — it must NOT widen to a *soft* double (that's backwards).
- On xtensa the hardware single FPU is the **native `Real` path**, not a deferred
  optimization. Only explicit `Double` goes soft on xtensa.
- PXX currently hardwires `Real`=tyDouble on all targets (parser.inc:6513,6552);
  this ticket makes the `Real` resolver target-aware (Double on double-HW,
  Single otherwise). Small parser change. Affects no-FPU/ESP precision of `Real`
  code by design (the contract).

## Dependencies

- [[feature-softfloat-lib]] — soft-**single** (riscv) + soft-**double** (both ESP)
  kernels + i<->s / i<->d / s<->d conversions this wiring calls. (On double-native
  targets Single stays storage-only/widen — unchanged, not part of this ticket.)

## Approach (per target, after the lib lands)

0. Make the `Real` resolver target-aware (parser.inc ~6513/6552): Double on
   double-HW targets, Single on xtensa/riscv. Small, do first.
1. Value model: Single = 4 bytes in a core reg (riscv) or HW single reg (xtensa);
   Double = raw bits in a core-register pair (riscv a0:a1, xtensa a-pair),
   mirroring arm32's d0->r0:r1 spill.
2. Lower the float IR nodes (`ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`):
   literal, IR_LOAD_SYM / STORE (slot moves at the type's width), binops, intrinsics,
   conversions, then params + returns. Dispatch per the matrix:
   - riscv32: single ops -> soft-single helpers; double ops -> soft-double helpers.
   - xtensa: single ops -> hardware single FPU insns; double ops -> soft-double
     helpers; a single<->double convert is a soft repack (no HW double).
3. Relax the EmitProcEpilog float guards last (symtab.inc ~3713 xtensa /
   ~3753 riscv32) — only once arithmetic + params are correct.
4. Add float tests to the ESP/cross suites; QEMU output-equality vs the x86-64
   oracle (ESP self-host is not a goal — device RAM too small).

## Follow-on option: `{$FASTDOUBLES ON}` (xtensa speed/precision knob)

A compiler switch (default OFF) that, on targets where **Double is soft but Single
is hardware** (xtensa today; any future single-FPU-no-double part), computes
`Double` arithmetic by round-tripping through the hardware single FPU
(double->single, do the op in HW, single->double) instead of calling the
soft-double kernels. Lets the user trade precision for speed **without editing
source** that happens to use `Double`.

- Default OFF = correct IEEE double (soft) — never silently lossy.
- ON = fast but lossy (results carry single precision). Documented as such.
- No-op where it can't help: double-native targets (already HW) and riscv (no
  single FPU either — both widths soft, nothing to cheat with).
- Directive name: `{$FASTDOUBLES ON|OFF}` (alts considered: `{$DOUBLEASINGLE}`,
  `{$LOSSYDOUBLES}`). Honest framing in the docs: it is NOT real double precision.
- Sequencing: post-baseline — needs xtensa soft-double + the hardware single FPU
  path working first. Implement as a lowering switch in `ir_codegen_xtensa.inc`:
  when set, a Double binop emits convert+HW-single+convert instead of the
  soft-double call.

## Notes

- Order within: literal+load/store+`dcmp` first (unblocks comparisons/branches),
  then add/sub, mul/div, conversions, params/returns.
- error-not-miscompile: leave each unimplemented piece erroring; never ship silent
  garbage.
- The float-return/param recipe from [[feature-cross-float-returns]] applies
  verbatim once arithmetic exists.
