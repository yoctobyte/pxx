---
track: B
prio: 65
type: bug
status: done
owner: claude-B
---

# `FloatToStrSig` caps at 15 significant digits, so no double round-trips

- **Type:** bug / missing capability (RTL) — **Track B** (`lib/rtl/sysutils.pas`)
- **Found:** 2026-08-01, blocking
  [[bug-nilpy-float-repr-not-shortest-roundtrip]].

## The cap

`lib/rtl/sysutils.pas:921`:

```pascal
if sig > 15 then sig := 15;      { past 15 a double scaled in doubles lies }
```

The comment is honest about why: the routine normalises the mantissa by
multiplying/dividing in DOUBLES, so past ~15 significant digits the scaling
itself introduces error and the extra digits would be fiction. Given that
algorithm, capping is the right call — the cap is not the mistake, the
algorithm's reach is the limitation.

## Why it needs lifting

An IEEE-754 double needs **up to 17 significant digits** to round-trip. At 15,
some values simply cannot be printed and re-read to the same bits. Measured with
a 1..17 round-trip probe (`StrToFloat(FloatToStrSig(d, p)) = d`):

| value | shortest p that round-trips | `FloatToStrSig(d, 17)` |
| --- | --- | --- |
| `25.4` | 3 | `25.4` |
| `0.1` | 1 | `0.1` |
| `0.1 + 0.2` | **never** | `0.3` |
| `1.0/3.0` | **never** | `0.333333333333333` |
| `2.834645669291339` | **never** | `2.83464566929134` |

So `FloatToStr` cannot be the basis of any exact float output, and anything
needing a faithful decimal form of a double is blocked.

## Fix shape

Exact decimal digit generation, which means NOT scaling in doubles:

- integer/bignum arithmetic over the 53-bit mantissa and binary exponent (the
  classic exact approach — this repo already has bignum machinery, e.g. the
  promotable-int path that computes 25! exactly), or
- a Grisu/Ryu-style shortest-representation algorithm.

Either gives correct digits to 17 and makes shortest-round-trip possible.

**Keep `FloatToStr`'s existing output contract unchanged** unless deliberately
changed: it is the shared Pascal path, so its formatting is observable by every
Pascal program and by test expectations across the tree. The safe shape is a new
exact entry point (and lifting the cap inside `FloatToStrSig` only once the
digits past 15 are real), not a behaviour change in place.

## Other spellings noticed while probing (same routine)

Not necessarily bugs for Pascal — recorded because the NilPy side has to
reconcile them:

| input | `FloatToStrSig` | Python `repr` |
| --- | --- | --- |
| `5.0` | `5` | `5.0` |
| `1.0e20` | `1E20` | `1e+20` |
| `-0.0` | `0` | `-0.0` |
| NaN / Inf | `NaN` / `Inf` | `nan` / `inf` |

## Gate

A round-trip test over a spread of doubles — including `0.1+0.2`, `1/3`,
denormals, very large/small magnitudes, and negative zero — where
`StrToFloat(exact_repr(d)) = d` for every case, and Pascal's own `writeln` of a
Double is byte-unchanged.

## Resolved 2026-08-02 — exact digit generation, no scaling in doubles

`lib/rtl/sysutils.pas` gained an exact decimal expansion for doubles and two
entry points on top of it:

- `FloatToStrExact(value, sigDigits)` — correctly rounded to N significant
  digits, half-to-even on the **exact** remainder (`%.*g`'s rule).
- `FloatToStrShortest(value)` — the shortest spelling that reads back identical.

The method is the second option this ticket listed, integer arithmetic over the
mantissa: a double is `mant * 2^exp2` with `mant` a 53-bit integer, and
`2^-k = 5^k * 10^-k`, so the exact decimal is the integer `mant*5^k` with the
point pushed `k` places (or `mant*2^exp2` outright when `exp2 >= 0`). Digits are
held little-endian one per byte and grown by multiply-by-small; multiplying in
chunks of `5^13` / `2^30` (the largest powers whose per-digit product stays well
inside `Int64`) keeps the denormal worst case — `exp2 = -1074`, 767 digits — at
~83 passes instead of 1074. Nothing anywhere scales in doubles, so every digit
emitted is a real digit of the value.

**Verified against an oracle, not read back.** A differential sweep of **3997
doubles** built from random bit patterns (xorshift64, with denormals and
positives deliberately over-sampled) compared `FloatToStrExact(d, 17)` against
CPython's `'%.17g' % d` **and** checked `float(s) == d`: **0 mismatches**. The
values this ticket tabulated now come out as CPython has them —
`1/3` → `0.33333333333333331`, `0.1+0.2` → `0.30000000000000004`,
`25.4` → `25.399999999999999`, DBL_MAX → `1.7976931348623157E308`, smallest
denormal → `4.9406564584124654E-324`.

**The `FloatToStr` contract is deliberately unchanged.** `FloatToStrSig` keeps
its own path for `sig <= 15` and defers to the exact one only past 15, exactly
as this ticket asked — the cap is lifted without perturbing the shared Pascal
output that test expectations across the tree pin. All 22 pre-existing
assertions in `test/lib_floattostr.pas` still pass unmodified.

### The round-trip half of the gate is NOT fully met — and it is not the writer

`StrToFloat(FloatToStrExact(d, p)) = d` still fails for every `p` on `1/3`,
`1e-300`, `DBL_MAX` and the smallest denormal. The strings are correct (CPython
reads all four back to the identical double); the **parse** loses them.
`StrToFloatDef` accumulates in doubles with one rounding per fractional digit
and builds `10^e` by `e` successive multiplies — the same "scale a double and
hope" shape, on the read side. Split out with measurements as
[[bug-b-strtofloat-not-correctly-rounded]] rather than folded in here, since it
is a separate defect with its own fix (a Clinger fast path plus a correction
slow path) — and the exact expansion added here is what that fix will use to
compare candidates. `FloatToStrShortest` is correct but not always *shortest*
until it lands: it verifies candidates with `StrToFloat`, so a wrong parse
rejects a valid shorter spelling.

Tests: `test/lib_floattostr.pas` gained 18 assertions, every expectation taken
from CPython.

## Log
- 2026-08-02 — resolved, commit df0bf0182.
