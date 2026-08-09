---
track: U
prio: 40
type: decide
---

# decide: should WriteLn's default float format follow the STATIC type, and should untyped float constants evaluate at Single precision?

- **Type:** decision (Track U) — escalated, not guessed
- **Measured:** 2026-08-09, an FPC differential that turned up two related
  divergences in one program. Both are *model* choices, not defects with an
  obviously right answer, which is why this is a `decide-` and not a `bug-`.

## The measurement (x86-64, `{$mode objfpc}`)

| written | FPC | pxx |
| --- | --- | --- |
| `WriteLn(-1.5 * 2.0)` | `-3.000000000E+00` | `-3.0000000000000000E+000` |
| `d: Double; WriteLn(d)` | `-3.0000000000000000E+000` | same ✓ |
| `s: Single; WriteLn(s)` | `-3.000000000E+00` | `-3.0000000000000000E+000` |
| `e: Extended; WriteLn(e)` | `-3.00000000000000000000E+0000` | `-3.0000000000000000E+000` |
| `WriteLn(1.0 / 3.0)` | `3.333333433E-01` | `3.3333333333333331E-001` |
| `d := 1.0 / 3.0; WriteLn(d)` | `3.3333334326744080E-001` | `3.3333333333333331E-001` |

Two distinct things:

1. **Default field width follows the static type in FPC** — 9 significant
   digits and a 2-digit exponent for Single, 17 and 3 for Double, 20 and 4 for
   Extended. pxx prints every float in the Double form.
2. **FPC evaluated the untyped constant `1.0 / 3.0` at SINGLE precision** — the
   last row is the tell: the Double variable holds `0.33333343`, the
   single-rounded value, not `0.33333333`. pxx computes it at double.

## The fork

**A. Match FPC on both.** Faithful to the policy's first rule (semantics of
accepted code track FPC). Cost: `WriteLn` must know each argument's static float
type, and constant folding must reproduce FPC's precision choice — which is the
part that gives *less accurate* answers than pxx does today.

**B. Match the FORMAT (1) but keep double-precision constants (2).** The output
divergence is what a test diff actually trips over; the precision one makes pxx
strictly more accurate and is invisible unless compared against FPC.

**C. Keep pxx's uniform double behaviour and document both rows.** Cheapest;
pxx's numbers are the better ones. Cost: any FPC-oracle test that prints a
Single or an untyped float constant differs, forever, and someone re-measures
this every time.

## Recommendation

**B.** (1) is a presentation rule with no accuracy cost and is what makes
differential testing against FPC quiet; (2) is FPC reproducing a historical
Turbo Pascal precision choice, and deliberately being *more* accurate than the
oracle is a defensible dialect position — the kind of thing
`meta-dialect-extensions-and-fpc-strict` exists to record. If (2) is wanted for
parity anyway, it belongs behind a strict flag, not in the default.

Not urgent: no correctness bug depends on it. It is filed because the next
person to run a float differential will otherwise re-derive the same table.
