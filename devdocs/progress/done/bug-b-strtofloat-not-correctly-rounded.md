---
track: B
prio: 60
type: bug
status: done
owner: claude-B
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

## Resolved 2026-08-02 — exact reconstruction, not a better approximation

Both paths described above landed, plus a third thing the shape needed.

**Fast path (Clinger).** Significand under 2^53 and `|expo| <= 22`: both the
significand and `10^|expo|` are exactly representable, so one multiply or
divide is one rounding and is therefore already correctly rounded. `10^k` is
built by repeated multiplication rather than a table of literals — deliberately,
since parsing float literals is the very thing being fixed, and repeated
multiplication is provably exact up to `10^22`. This covers the large majority
of real input (JSON numbers and the like) at roughly the old cost.

**Slow path — search, not estimate.** Rather than estimating and hoping, the
value is found by an ordered search over the IEEE **bit pattern**: for positive
doubles the bit pattern increases monotonically with the value, so "largest
double <= D" is a plain binary search, and every comparison is against the
candidate's *exact* decimal expansion (the machinery added by
[[bug-b-floattostrsig-caps-at-15-significant-digits]]). Nothing here can be off
by an unknown number of ULP, because nothing here is approximated.

The final choice between that double and the next one up is made against their
exact midpoint, `(2*mant + 1) * 2^(exp2 - 1)`. That single formula holds
everywhere — including across a power-of-two boundary and across the
denormal/normal boundary — because incrementing the bit pattern is exactly what
both transitions are. The midpoint needs 54 bits and so is not a Double, which
is why the expansion routine was refactored to take a mantissa and exponent
rather than a Double. Ties go to the even mantissa.

Out-of-range inputs fall out of the same search instead of needing guards:
below the smallest denormal it settles on bits 0 and rounds to zero; above
DBL_MAX it settles on DBL_MAX, whose next bit pattern *is* +Inf.

**Performance — measured, because the first correct version was too slow.**
Naive exact search cost 0.76 ms per ordinary 17-digit parse and 41 ms per
denormal, which is not shippable. Two changes, each measured:

| | 17-digit | denormal | DBL_MAX |
| --- | --- | --- | --- |
| first correct version | 0.76 ms | 41 ms | 10 ms |
| bignum in base 10^9 limbs | 0.57 ms | 14 ms | 4 ms |
| \+ search seeded from a float estimate | **0.04 ms** | **1 ms** | **<0.1 ms** |

Base 10^9 is a ~9x cut in the inner loop and is what makes the exact expansion
affordable on *both* sides, since the search pays for an expansion per step
rather than once. The seed is a plain float estimate used only to bracket the
search by doubling steps — it is never trusted, and if it were wildly wrong the
doubling simply degenerates to the unseeded search, still correct. That
combination is 19x on the common case and 41x on denormals. The fast path is
unchanged and still effectively free.

**Verified against an oracle.** A 4996-value differential sweep (random bit
patterns, denormals over-sampled), rendering each double at 15, 16 and 17
significant digits and reading it back:

- writer vs CPython's `'%.Ng' % d` at each N: **0 mismatches**
- `StrToFloat(s)` vs CPython's `float(s)`, i.e. correct rounding: **0 mismatches**
- `FloatToStrShortest` round-trips and is as short as CPython's `repr`: **0 mismatches**

The four values this ticket opened on now all round-trip, and
`FloatToStrShortest` matches `repr` exactly: `1/3` → `0.3333333333333333`,
`1e-300` → `1E-300`, DBL_MAX → `1.7976931348623157E308`, smallest denormal →
`5E-324`. Also checked individually and matching CPython: `9007199254740993`
(2^53+1, a genuine tie, rounds half-to-even down to 2^53),
`2.2250738585072011e-308` (the value that famously hung Java's and PHP's
`strtod`), a 30-digit integer, `1e999` → `Inf`, `1e-999` → `0`.

**The acceptance contract did not move.** Malformed input still returns `def`
(`'1e'`, `'1e+'`, `'abc'`, `''`, `'1.2.3'`, `'1 2'`, `'1e5x'`, `'--1'`), and
the accepted spellings still parse (`'  -2.5'`, `'+3'`, `'.5'`, `'5.'`,
`'000123.4500'`, `'1.2E+003'`, `-0.0`). Those cases are pinned in the test now,
since a rewritten parser is exactly where acceptance quietly drifts.

Tests: `test/lib_floattostr.pas` is up to 68 assertions (22 pre-existing, all
still passing unmodified).

## Log
- 2026-08-02 — resolved, commit PENDING.
