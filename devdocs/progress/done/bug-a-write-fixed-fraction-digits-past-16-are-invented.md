---
summary: "SILENT: write(v:w:d) gets the INTEGER part exactly now, but the fraction is still scaled through a Double — 1/3 at :0:30 prints ...333312 where the double's exact tail is ...333314829616256247, so digits 17-18 are wrong and 19+ are zeros presented as digits"
type: bug
track: A
prio: 35
status: done
owner: claude-A
---

# `write(v:w:d)`: the fraction past ~16 digits is an approximation, padded with zeros

- **Type:** bug — **SILENT wrong output**, same class as
  [[bug-a-write-fixed-emits-false-digits-past-1e22]], other half of the number.
  Track A (`compiler/builtin/builtinheap.pas`, `PXXWriteFloatFixed`).
- **Opened:** 2026-08-06, measured while fixing the integer part. Not a
  regression — this half was never exact.

## Measured (oracle: `decimal.Decimal(float(x))`, exact)

    (1/3):0:30    pxx   0.333333333333333312000000000000
                  exact 0.333333333333333314829616256247
                  FPC   0.333333343300000000000000000000   (worse; not an oracle)

    0.1:0:25      pxx   0.1000000000000000000000000
                  exact 0.1000000000000000055511151

Two shapes, both silent:

- **digits 16-18 are the product's rounding, not the value's digits** —
  `...312` where the value has `...314`;
- **everything past 18 is zeros**, presented as if the value ended there. For
  `0.1:0:25` the zeros start at digit 17 because `0.1 * 1e18` rounds to exactly
  `1e17`, so the printed answer is a clean `0.1` followed by twenty-four zeros
  and not one digit of the real tail.

## Cause

The fraction is scaled by a Double multiply and then divided down, and the
routine's own comment records the padding as deliberate:

```pascal
  v := (x - ip) * pw + 0.5;      { pw = 10^fdigits, fdigits capped at 18 }
  ...
  i := fdigits + 1;
  while i <= decimals do     { past what a double knows: zeros, not guesses }
    write('0');
```

"Past what a double knows" is the false premise. A double is
`mant * 2^exp2` with both parts integral, so its decimal expansion is finite
and **exact** — a denormal runs to 767 digits and every one of them is a real
digit. The cap at 18 is a property of the Int64/Double scaling, not of the
value.

## Fix

Same route the integer part just took: expand exactly in base-10^9 limbs. The
machinery is in the same unit (`PxxSciMul` / `PxxSciSplit` / `PxxIntDDigits`),
but the fraction needs the `exp2 < 0` half of the expansion (multiply by 5^k)
plus digit extraction at an arbitrary offset with half-away-from-zero rounding
at the cut. `lib/rtl/sysutils.pas`'s `FmtFixed` is the worked example — it does
exactly this for `Format('%.Nf')` and matches the exact value at every
magnitude and precision.

Note this is the *fixed* path only. `PXXWriteFloatSci` is already exact
(`PxxSciDigits17`).

## Why it is low priority despite being silent

It only bites past ~16 fraction digits, where FPC is also wrong (differently),
and no correct program can be relying on the current answer. Contrast the
integer half, which broke at magnitudes a program reaches by accident.

## Related

- [[bug-a-write-fixed-emits-false-digits-past-1e22]] — the integer half, fixed.
- [[decide-float-fixed-output-exact-or-fpc-17-digit-cap]] — the display-policy
  question. If that lands on "cap at 17 significant digits", this ticket
  becomes "print zeros ONLY past the cap, and the digits below it exactly",
  which is still a change: today digits 16-18 are wrong, not capped.
- [[compat-pascal-write-fixed-huge-magnitude-differs-from-fpc]] — the
  `Str(v:w:d)` side, which bails to an exponent form past 9.2e18.

## Gate

`write(v:0:d)` for d up to 30 matches `decimal.Decimal(float(x))` quantized
half-away-from-zero, on every target; `test/lib_writefloat_fixed.pas` extended
with the cases above.

## 2026-08-07 — assessed, not started; and the DECISION is now unblocked

Two findings worth recording so the next attempt starts from them.

**1. The blocking decision is ready for Track U.**
[[decide-float-fixed-output-exact-or-fpc-17-digit-cap]] is `blocked-by:
bug-a-write-fixed-emits-false-digits-past-1e22` — and that ticket is **done**.
So the decision is unblocked and is the gating question for this one: it decides
whether the target is "every digit exact" or "exact below a 17-significant-digit
cap, zeros above". Both are a change from today (digits 16-18 are currently
*wrong*, not capped), but they are different implementations.

Worth noting for whoever answers it: pxx **already** prints the INTEGER half
exactly, on all five targets, matching CPython against FPC's cap. So today the
two halves of one number follow different rules — the integer part exact, the
fraction approximated — which is an argument for "exact" on consistency grounds
alone, independent of the FPC-parity question.

**2. The fix is bigger than "port FmtFixed", because of the mirroring rule.**
`PXXWriteFloatFixed` (builtinheap.pas) carries an explicit contract in its own
header: *"Mirrors EmitWriteFloatFixed (x86-64), and must keep mirroring it: this
is the i386 / arm32 / riscv32 route to the same output, so a program's text must
not depend on which backend built it."* So an exact base-10^9 expansion has to
land in the **hand-emitted x86-64 float writer** as well as the portable body,
or the targets diverge — and diverging text across backends is a worse bug than
the one being fixed.

The honest shape is therefore to route both to ONE shared Pascal helper, the way
the sci path already routes to `PxxSciDigits17` (`PXXWriteFloatSci` is exact
precisely because it does this). That is the real task: not a numeric tweak but
removing a hand-written duplicate, which is also what stops this pair drifting
again.

Left in backlog at prio 35. It wants a session that can hold the emitter change
and run the cross-target gate.

## Resolution (2026-08-11) — and the mirroring worry was already gone

The 2026-08-07 note said the fix had to land in the hand-emitted x86-64 float
writer as well, or the backends would print different text. That is no longer
true: `EmitWriteFloatFixed` is already a SHIM onto `PXXWriteFloatFixed` (the
native emitter survives only as a fallback for when the helper is absent), and
i386 / arm32 / aarch64 / riscv32 all call the same routine. So there is ONE
implementation, and this is a numeric change after all.

New `PxxFracDigits` expands the fraction exactly, in the same base-10^9 limbs
its integer sibling `PxxIntDDigits` uses — the `exp2 < 0` half, multiplying by
5^k, since 2^-k = 5^k * 10^-k makes the value the integer `mant*5^k` with the
point pushed k places left. Rounding is half-away-from-zero at the cut, decided
by the first DROPPED digit (which answers both the >half and the exact-tie case,
and an exact tie really is one here — nothing is scaled). It is called twice:
once with `emit = 0` to learn whether rounding carries into the integer part
(that changes both the integer digits and the column count, `9.96:0:1` → `10.0`)
and once to print. `PXXWriteFloatFixed` lost its `pw`/`rem`/`dv` scaling
entirely — both halves of the number now follow one rule.

Matches `decimal.Decimal(float(x))` quantized half-away-from-zero on every row
measured, including the ticket's two:

    (1/3):0:30   0.333333333333333314829616256247   (was ...312 then zeros)
    0.1:0:25     0.1000000000000000055511151        (was twenty-four zeros)
    1e-320:0:325 the full 320-digit denormal expansion, ending 99999

plus 267.5:0:20 (an exact binary value — really is all zeros), the 0.5/1.5/2.5
half-away-from-zero row, a negative, a carry into the integer, a field width,
and 1e20:0:2. Identical output on x86-64, i386, arm32 and aarch64; 147-file
float/str/format family sweep against `pinned` with no unintended diffs.

**riscv32 diverges on ONE row and it is not this bug:** it folds `1/3` to a
SINGLE-precision value (`0.33333334326744079590` is float32's 1/3), which the
old approximate fraction hid because nobody could print far enough to see it.
Pre-existing on `pinned`; filed as
`bug-a-riscv32-folds-a-double-literal-division-to-single-precision`.

`test/lib_writefloat_fixed.pas` extended with the fraction rows. Needs a pin
before other lanes see it (`compiler/builtin`).

## Log
- 2026-08-11 — resolved, commit d7e7dab2d.
