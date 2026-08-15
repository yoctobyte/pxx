---
track: A
prio: 60
type: bug
blocked-by: []
summary: "TWO facets. (1) Int(1.0e300) returns -9.2233720368547758E+018 (INT64_MIN) on x86-64. (2) Int(-0.5) returns +0.0 where FPC and C give -0.0, which alone accounts for 443 of 443 SimpleRoundTo divergences from FPC. FPC returns 1e300. Int() is defined on DOUBLES and must not visit an integer at all: for |x| >= 2^52 every double is already integral, so Int(x) IS x. The i386/arm32 half of this was fixed under bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32; x86-64 was never in scope and is still wrong. Frac(x) is wrong at the same magnitudes."
status: done
owner: agent-an-night
---

# `Int()` of a large double is `INT64_MIN` on x86-64

- **Type:** bug (builtin — **Track A**). Filed by Track B, which found it and
  does not edit the compiler.
- Found 2026-08-15 while fixing `FMod` in `lib/rtl/math.pas`. Sibling of
  [[bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32]], which
  is **done** and fixed the 32-bit targets only.

## Measured, pinned v339, x86-64

```
Int(3.5)      3.0                       correct
Int(1.0e18)   1000000000000000000.0     correct
Int(3.3e299)  -9.2233720368547758E+018  WRONG
Int(1.0e300)  -9.2233720368547758E+018  WRONG
```

FPC 3.2.2:

```
Int(1.0e300)   1.00000000000000000001E+0300
Int(3.3e299)   3.29999999999999999999E+0299
Frac(1.0e300)  0.00000000000000000000E+0000
```

`-9.2233720368547758E+018` is `INT64_MIN`, the x86 "integer indefinite" result.
So the builtin is still going through a 64-bit integer conversion. The 32-bit
targets saturated at 2^31 and x86-64 lands on INT64_MIN — **one defect, two word
sizes**, and the earlier fix addressed the symptom on two backends rather than
the cause.

## The fix needs no conversion at all

`Int` returns a DOUBLE. For |x| >= 2^52 every double is already an integer, so
there is nothing to truncate:

```
if Abs(x) >= 4503599627370496.0 then Result := x      { 2^52 }
else <the existing Int64 route, which is safe below 2^52>
```

A magnitude test and an early return. `lib/rtl/math.pas`'s `DdRint` already
does exactly this and says why in a comment citing the older ticket.

## Second facet, same builtin: `Int` LOSES THE SIGN OF ZERO

Found the same day, auditing `SimpleRoundTo` against FPC:

| | pxx | FPC | C's `trunc()` |
| --- | --- | --- | --- |
| `Int(-0.5)` | `+0.0` | **`-0.0`** | `-0.0` |
| `Int(-0.9)` | `+0.0` | **`-0.0`** | `-0.0` |
| `Int(-0.0)` | `+0.0` | **`-0.0`** | `-0.0` |
| `Int(-1.5)` | `-1.0` | `-1.0` | `-1.0` |

`Int` truncates toward zero, so for x in (-1, 0] the true result is **negative
zero** — IEEE 754 keeps the sign, and so do FPC and C. Only the magnitude-zero
cases are affected, which is why it survived: `Int(-1.5)` is right.

It matters downstream. `lib/rtl/math.pas`'s `SimpleRoundTo` is FPC's own formula
(`Int(AValue*RV - 0.5) / RV`), and it diverges from FPC on **443 of 2,937**
compared cases — every single one a `+0.0` where FPC gives `-0.0`, and **zero
genuine value differences**. Fix `Int` and all 443 go away. `RoundTo` matched
FPC on all 2,937 because its formula routes through `Round`, not `Int`.

(Methodology note for whoever verifies: FPC's untyped real constants are
Extended, so any input built from literal arithmetic hands the two compilers
DIFFERENT doubles — 338 of 520 differed that way on a first attempt, which made
`RoundTo` look broken when it is not. Build the inputs from `Int64` bit patterns
reinterpreted through a pointer.)

## Also wrong: `Frac`

`Frac(x) = x - Int(x)`, so it inherits this at the same magnitudes. FPC gives
`Frac(1e300) = 0`. Check whether `Frac` is implemented in terms of `Int` or
separately, and fix both — per
`devdocs/dev/normalise-dont-special-case.md`, if the two have separate
implementations the second one is the one that stays broken.

## Not blocking the RTL

`lib/rtl/math.pas`'s `FMod` used to be `x - Int(x/y)*y` and returned
`FMod(1e300, 3.0) = 1e300` because of this. Track B replaced it with an exact
scaled-subtraction loop that never calls `Int`, so the RTL no longer depends on
the builtin being right. This ticket stands for user code and for `Frac`.

## Gate

`make test` + self-host byte-identical, plus `Int` and `Frac` matching FPC 3.2.2
at 1e300, 3.3e299, 2^52, 2^52-0.5, 2^63, and the negatives of each — on
x86-64 **and** the 32-bit targets, so the earlier fix is not regressed.

## Resolution (2026-08-15): already fixed at HEAD by 5b6e1728d — verified, both facets

`fix(A): Int/Frac stay in the float domain on all five targets` (5b6e1728d,
landed after this ticket's pinned-v339 measurements) is exactly the fix this
ticket asks for, and it went further than the write-up: `EmitTruncToIntegralX64`
does the pure bit manipulation (clear the fractional mantissa bits selected by
the exponent), so inf/NaN pass through, |x| >= 2^52 is returned unchanged, and
|x| < 1 becomes a SIGNED zero. No integer register appears in the lowering, so
there is no range to run out of. i386 got `EmitTruncToIntegral386` (x87
`frndint` with RC=truncate); riscv32/xtensa already routed through `__pxx_dint`.

Verified at HEAD (c304fca4d + this session's commits), self-hosted build:

- **FPC 3.2.2 oracle, byte-identical output** on all 15 cases the Gate section
  names — `Int` at 3.5, -0.5, -0.9, -1.5, 1e18, 3.3e299, 1e300, -1e300, 2^52,
  2^52-0.5, ±2^63, and `Frac` at 1e300, -0.5, 2.75. `Int(1e300)` = 1e300 (was
  INT64_MIN); `Int(-0.5)` = `-0.0` (was `+0.0`).
- **All five targets agree with FPC byte for byte**: x86-64 native, i386
  native, aarch64 / arm32 / riscv32 under qemu. The earlier 32-bit fix is not
  regressed.
- **The downstream claim holds.** 3000 pseudo-random doubles built from `Int64`
  BIT PATTERNS (per the ticket's own methodology note, so both compilers see
  the same double), compared as bit patterns of the result: `SimpleRoundTo(d,-2)`,
  `SimpleRoundTo(d,-4)` and `RoundTo(d,-2)` are **bit-identical to FPC on all
  9000 comparisons** — 0 divergences, where the ticket measured 443.

  (Comparing the same sweep as *printed text* shows a difference that is NOT a
  value difference: FPC's `Write(x:0:20)` stops at ~17 significant digits and
  pads zeros, pxx prints the full decimal expansion. Worth knowing before
  someone reads it as a regression.)

No code change needed. Closing as fixed-elsewhere.

## Log
- 2026-08-15 — resolved, commit b347f71cf.
