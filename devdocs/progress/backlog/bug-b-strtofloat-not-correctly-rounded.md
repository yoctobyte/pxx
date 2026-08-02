---
track: B
prio: 60
type: bug
---

# `StrToFloat` is not correctly rounded, so exact decimals still do not read back

- **Type:** bug (RTL, silent wrong value) — **Track B** (`lib/rtl/sysutils.pas`)
- **Found:** 2026-08-02, while landing
  [[bug-b-floattostrsig-caps-at-15-significant-digits]]. The write side is now
  exact; this is the other half of that ticket's round-trip gate.

## Measured

With `FloatToStrExact` producing digits verified exact against CPython
(3997-value differential sweep, 0 mismatches), the round-trip
`StrToFloat(FloatToStrExact(d, p)) = d` **still fails for every p = 1..17** on:

| value | exact 17-digit form (correct) | round-trips? |
| --- | --- | --- |
| `1.0/3.0` | `0.33333333333333331` | **no, at any p** |
| `1e-300` | `1E-300` | **no** |
| `DBL_MAX` | `1.7976931348623157E308` | **no** |
| smallest denormal | `4.9406564584124654E-324` | **no** |

The strings are right — CPython reads all four back to the exact same double.
It is the parse that loses them.

A visible consequence today: `FloatToStrShortest(1/3)` returns the 17-digit
`0.33333333333333331` instead of CPython's 16-digit `0.3333333333333333`,
because it verifies candidates with `StrToFloat` and the 16-digit one is
rejected — a correct-but-not-shortest answer, produced by a wrong parse.

## Cause

`StrToFloatDef` (`lib/rtl/sysutils.pas:1297`) accumulates in doubles:

```pascal
divsor := divsor * 10.0;
frac := frac + (digit * 1.0 / divsor);   { one rounding per fractional digit }
...
for k := 1 to e do scale := scale * 10.0; { e roundings — e is up to 308 }
if eneg then w := (w + frac) / scale else w := (w + frac) * scale;
```

Three separate error sources, none of them bounded to the half-ULP a correct
`strtod` guarantees:

1. one rounding **per fractional digit** in `frac`;
2. `10^e` built by `e` successive multiplications — at `e = 300` the power
   itself is already tens of ULP off, which is why `1e-300` and `DBL_MAX` fail;
3. a final multiply/divide on top.

Same family as the write-side bug that was just fixed — "we scale a double and
hope" — and the same fix direction: do not scale in doubles.

## Fix shape

Correct rounding needs the parse to reach the right double in **one** rounding:

- **Fast path (Clinger):** significand in an `Int64` and `|exp10| <= 22`, with
  the significand `<= 2^53` — then `sig * 10^e` / `sig / 10^-e` off an exact
  power-of-ten table is a single rounding and provably correct. Covers most
  real input, but *not* the 17-digit significands a round-trip needs
  (`33333333333333331 > 2^53`), which is precisely the case this ticket is
  about.
- **Slow path:** an estimate, then correction by exact comparison. The exact
  decimal expansion of a candidate double is now available in this same unit
  (`ExDecDigits`, added for the write side), so a candidate can be compared
  against the input digits exactly and walked to the neighbouring double.
  Deciding between two neighbours means comparing `2*input` with
  `exact(c) + exact(next)`, which needs decimal bignum add/compare on the same
  little-endian digit buffers `ExDecMul` already uses.

The estimate must be good to a handful of ULP or the correction walk is long —
build `10^e` by binary splitting off a power table (~9 roundings) rather than
`e` successive multiplies.

## Gate

`StrToFloat(FloatToStrExact(d, 17)) = d` for a spread of doubles including
`0.1+0.2`, `1/3`, `1e-300`, `DBL_MAX`, denormals and negative zero — plus a
differential sweep against CPython's `float(s)` over random bit patterns, which
is how the write side was verified. `test/lib_floattostr.pas` is where the
cases belong; its `FloatToStrShortest` expectations should then shorten to
CPython's `repr` for all of them.
