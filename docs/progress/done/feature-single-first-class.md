# Single (32-bit float) first-class on the internal-call ABI

- **Type:** feature (float type model / ABI)
- **Status:** DONE (2026-06-21)
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Closed:** 2026-06-21

## Problem

`Single` (tySingle, 4-byte IEEE-754) was not first-class on the INTERNAL
(PXX-ABI) call path. Passing a Single value to a Single parameter, or returning a
Single, produced 0.00. Only the EXTERNAL C-call path narrowed/widened at the
tySingle boundary; the internal path carried floats as DOUBLE bits and never
narrowed at the param/return boundary. Subsumes
feature-double-to-single-narrowing.

## Root cause (per target)

The IR float value model carries floats as DOUBLE bits in the GPR (rax / x0 /
eax:edx / r0:r1). At the Single boundary the bits must be narrowed (cvtsd2ss /
fcvt s,d / vcvt.f32.f64) so a 4-byte slot holds true single bits, and widened
back on load. The gaps were NOT uniform:

- **x86-64**: internal call pushed double bits in an integer register; the callee
  prologue stored the low dword of the double bits into the 4-byte Single slot =
  garbage. The Single VAR load (EmitLoadVar movss+cvtss2sd) and the Single RETURN
  (epilog EmitLoadVar widens, store narrows) were already correct — only the
  prologue param spill was missing the narrow.
- **aarch64**: same as x86-64 — internal call carried double bits in x[i]; the
  prologue `str w[i]` stored garbage. Return/var-load already correct.
- **i386**: caller-side bug — the Single arg path did `movss [esp], xmm0` WITHOUT
  a preceding `cvtsd2ss`, so it pushed the low dword of the double bits. (Prologue
  + return already fine: caller narrows, callee copies 4 bytes, return widens.)
- **arm32**: already correct — caller narrows (vcvt.f32.f64 s0,d0; vmov r0,s0;
  push 1 word); prologue stores 4 bytes single bits; return widens.

## Fix

1. **x86-64 prologue** (parser.inc, both the <=6-register and >6-stack spill
   loops): for a by-value tySingle param, `movq xmm0,<reg>` / `cvtsd2ss` /
   `movss [rbp+off],xmm0` instead of the raw integer store.
2. **aarch64 prologue** (parser.inc, i<8 branch): `fmov d0,x[i]` / `fcvt s0,d0` /
   `str s0,[x8]`.
3. **i386 caller** (ir_codegen386.inc): add `cvtsd2ss xmm0,xmm0` before the
   `movss [esp],xmm0` Single-arg push.
4. **Overload clause** (symtab.inc TypesCompatible): a float formal accepts any
   float actual (widen/narrow) or an ordinal actual (int->float), compatible-match
   only (after exact match). Added LAST, after the ABI, so `ScaleS(1.5,3)` no
   longer silently compiles to 0.00.

## Acceptance / gates

- test/test_single_first_class.pas — Single var/literal/Double-narrow as arg,
  Single param read+arith, Single function return, int->Single, mixed Integer.
  Wired into `make test` (x86-64).
- Single case re-enabled in test/test_cross_float_return.pas; runs in the
  i386/aarch64/arm32 cross suites (output-equality vs the x86-64 oracle).
- `make test` green; self-host byte-identical; `make cross-bootstrap` byte-
  identical on i386/aarch64/arm32; ESP (xtensa/riscv32) still builds
  (test_esp_bare both archs). ESP soft-float routing of Single ops is downstream
  feature-esp-float work — out of scope here.

## Notes / landmines

- The double-bits value model is the through-line: Single is narrowed only AT the
  4-byte boundary (slot store / arg push) and re-widened on every load. Keeping
  the in-register model as double bits is what lets the rest of the float codegen
  stay target-uniform.
- Two targets (x86-64, aarch64) narrow in the CALLEE prologue (caller pushes
  double bits in a GPR); two (i386, arm32) narrow in the CALLER (push 4-byte
  single). Don't assume one convention across targets.
