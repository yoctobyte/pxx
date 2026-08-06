---
summary: "SILENT: write(v:w:d) gets the INTEGER part exactly now, but the fraction is still scaled through a Double — 1/3 at :0:30 prints ...333312 where the double's exact tail is ...333314829616256247, so digits 17-18 are wrong and 19+ are zeros presented as digits"
type: bug
track: A
prio: 35
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
