---
track: U+F
prio: 10
type: decide
status: postponed
postponed: 2026-08-10
---


## POSTPONED 2026-08-10 — the DEFAULT format is not a contract, so it does not matter

**User's call.** Moved to `rainy-day/`. Not rejected — the measurement below
stays useful — but explicitly not worth deciding now.

> "if the programmer _specifies_ the output (number of digits etc), we already
> follow that. if unspecified, we are free to do as we see fit. [...] the
> _default_ formatting is not relevant. programmer should specify number of
> digits he/she wants." — user

That is the same position `bug-nilpy-float-repr-loses-small-values-and-does-not-round-trip`
already reached and recorded:

> "What DOES matter is honouring an explicitly REQUESTED number of decimals
> (`%.15f`, `{:.3f}`, `FloatToStrF(v, n)`) — those paths are a contract, and they
> currently test correct."

So the split is settled even though this ticket is not: **specified precision is
a contract and is already honoured and tested; unspecified default output is
ours to choose.**

### Correction to the record — pxx does NOT do shortest-round-trip

Worth stating plainly because it was believed otherwise in conversation, and
because anything that relies on it would be relying on something that is not
there. pxx does **not** implement Steele & White / Dragon4 / Grisu / Ryū. That is
step 3 of the repr ticket and was explicitly deferred:

> "Shortest-round-trip digits. The real repr rule, and the largest change: it
> needs a Grisu/Ryu-style shortest-digit algorithm, not a scale-and-trim. Worth
> its own ticket and probably not worth it until something needs exact
> round-tripping."

What landed there was the value-LOSS fix (a nonzero number printing as `0`). The
renderer in `compiler/builtin/builtin.pas` is still scale-and-trim by decade
loops, and carries a documented DEAD END warning against re-attempting the
binary-decomposition normalisation.

**If exact round-tripping is ever needed** — streaming, serialisation, a
`repr()` that must reload identically — that is the ticket to open, and it is a
real algorithm, not a formatting tweak.

### Should this ever be revisited

The one argument that does not depend on FPC parity: printing 17 significant
digits for a `Single` prints digits the type cannot carry (24-bit mantissa
~= 7.2 decimal digits), e.g. pxx renders a Single 1/3 as
`3.3333334326744080E-001` where only `3.333333` is information. That is a
presentation-honesty argument rather than a compatibility one, and it is the
reason to reopen if anyone does.


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
