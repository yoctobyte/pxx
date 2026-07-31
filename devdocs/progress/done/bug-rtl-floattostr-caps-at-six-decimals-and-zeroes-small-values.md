---
track: B
prio: 35
type: bug
---

# `FloatToStr` keeps SIX decimal places, so it loses 9 digits FPC keeps — and returns `0` below 5e-7

```pascal
uses sysutils;
writeln(FloatToStr(1/3));           { FPC: 0.333333333333333   pxx: 0.333333 }
writeln(FloatToStr(0.000000123));   { FPC: 1.23E-7             pxx: 0        }
writeln(FloatToStr(1e-20));         { FPC: 1E-20               pxx: 0        }
writeln(FloatToStr(1e16));          { FPC: 1E16                pxx: 10000000000000000 }
```

Silent in every case. A value simply arrives with nine significant digits
missing, or as zero.

## Measured against FPC

| call | pxx | FPC |
| --- | --- | --- |
| `FloatToStr(1/3)` | `0.333333` | `0.333333333333333` |
| `FloatToStr(3.14159265358979)` | `3.141593` | `3.14159265358979` |
| `FloatToStr(0.000123456)` | `0.000123` | `0.000123456` |
| `FloatToStr(0.000000123)` | **`0`** | `1.23E-7` |
| `FloatToStr(1e-20)` | **`0`** | `1E-20` |
| `FloatToStr(1e-300)` | **`0`** | `1E-300` |
| `FloatToStr(1e16)` | `10000000000000000` | `1E16` |
| `FloatToStr(1e20)` | `1E+20` | `1E20` |
| `FloatToStr(2.5)` / `(100.0)` / `(1234567890.12345)` | correct | correct |
| `Format('%g', [1/3])` | `0.333333` | `0.33333333333333331` |
| `Format('%f', [1/3])` | `0.33` | `0.33` |
| `Format('%.15f', [1/3])` | `0.333333333333333` | `0.333333333333333` |

So the EXPLICIT-precision paths are right and the two NATURAL ones —
`FloatToStr` and `%g` — are wrong. Values with at most 6 decimals
(`2.5`, `100.0`, `1234567890.12345`) come out correct, which is why this
survived: the round numbers a test tends to use are exactly the ones that work.

## Root cause

`lib/rtl/sysutils.pas`, `FloatToStr` (≈905):

```pascal
  intPart := Trunc(value);
  fracPart := Round(Frac(value) * 1000000);      { <-- six decimal places, hardcoded }
```

Six DECIMAL places, not significant digits. `1/3` therefore rounds at the sixth
place, and anything below 5e-7 rounds `fracPart` to 0 with `intPart` already 0,
so the function returns `"0"`. There is an exponential path
(`FloatToExpStr`) but it is only reached from the LARGE guard
(`abs(value) > 9.2e18`); nothing routes small magnitudes to it.

FPC's rule is `FloatToStrF(value, ffGeneral, 15, 0)`: 15 SIGNIFICANT digits,
switching to exponential when the decimal exponent falls outside the fixed
window.

## Shape of a fix

Scale by significant digits rather than decimal places, and add the small-side
exponential guard that mirrors the large-side one already present:

- compute the decimal exponent first, then emit 15 significant digits;
- route to `FloatToExpStr` when the exponent is below the fixed window (FPC
  switches at <= -5 for the general format) as well as above it;
- `FloatToExpStr` itself calls `FloatToStr` for the mantissa, so fixing the
  significant-digit rule fixes the mantissa too — but check the recursion
  guard still holds once small values can enter that path.

Note the exponent SPELLING also differs — pxx writes `1E+20`, FPC writes
`1E20` — and should be settled in the same change.

## Related but separate

`FloatToStrF` has an incompatible SIGNATURE: pxx declares
`FloatToStrF(value: Double; precision: Integer)`, FPC declares
`FloatToStrF(value; format: TFloatFormat; precision, digits: Integer)`. Any
real FPC source calling it fails to compile. Worth its own `compat-pascal-*`
ticket rather than folding it in here.

The NilPy/`compiler/builtin` float renderer is a DIFFERENT implementation with
its own (15-decimal-place) version of the same small-value hole — see
[[bug-nilpy-float-repr-loses-small-values-and-does-not-round-trip]]. Fixing one
does not fix the other.

## Gate

`make lib-test` / `make demos`, plus a `.pas` diffed against FPC over the table
above. Watch for recorded expectations elsewhere that encode the 6-decimal
output — those expectations are the bug, the way
`test_nilpy_string_variant` was.

## Priority note 2026-07-30 (user)

Float REPRESENTATION divergence is explicitly low value here: a mantissa
landing on `9.999999999999995e+299` instead of `1e+300` is not considered a
bug worth chasing. What DOES matter is honouring an explicitly REQUESTED
number of decimals (`%.15f`, `{:.3f}`, `FloatToStrF(v, n)`) — those paths are
a contract, and they currently test correct. Deprioritised accordingly; the
value-LOSS half (a nonzero number printing as `0`) is the part that was worth
fixing and is done for the NilPy renderer.

## RESOLVED 2026-07-31 — the value-loss half is fixed, and the rest came with it

`FloatToStr` now implements FPC's actual rule — `FloatToStrF(value, ffGeneral,
15, 0)`: fifteen SIGNIFICANT digits, exponential form when the decimal point
falls outside `[-3, 15]`, and FPC's exponent spelling (`1E20`, `1.23E-7` — a
sign only when negative, no zero padding).

The normalisation deliberately steps by powers of TWO decades (1e1, 1e2, 1e4 …
1e256) rather than one at a time. One decade at a time meant up to 300 roundings
on a denormal, and that alone printed `1e-300` as `9.99999999999999E-301`; nine
roundings is enough for any finite double and gives `1E-300` exactly.

### Measured against FPC, not against pxx

Every expectation in the new `test/lib_floattostr.pas` was produced by an
FPC-built copy of that same program — the file compiles under both. All 22 rows
match, including the three that used to return the string `0`.

A wider differential over 490 values (400 random bit patterns reinterpreted as
doubles, plus a sweep of `1.0e-320` … `1.0e308`) diffed against an FPC build of
the identical generated program:

- **459 of 490 byte-identical.**
- **31 differ, all by exactly one unit in the 15th significant digit.**
- **0 structural divergences** — no zeros, no wrong exponents, no wrong form.

That residue is the representation half the priority note above calls explicitly
not worth chasing, and it is now bounded and measured rather than assumed.

### Left open, deliberately

`Format`'s `%g` inherits `FloatToStr` and so moved from 6 digits to 15, where
FPC gives 17; it also ignores an explicit `%.3g`, and `%e` has no branch at all
and is emitted literally. Those are a different rule from `FloatToStr`'s and are
split out as [[compat-pascal-format-g-and-e-specifiers]] rather than guessed at
here. `FloatToStrF`'s incompatible SIGNATURE remains its own item, as this
ticket already said.

### Gate

`tools/gate.sh lib` GREEN with `test/lib_floattostr.pas` wired into `lib-test`.

## Log
- 2026-07-31 — resolved, commit bc2a960ce.
