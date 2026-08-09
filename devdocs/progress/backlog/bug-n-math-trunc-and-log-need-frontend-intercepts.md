---
track: N
prio: 35
type: bug
summary: "math.trunc must return an int like CPython; math.log(x, base) must be CPython's unsnapped quotient rather than the FPC-faithful LogN; and math.pow/math.copysign cannot be RTL names at all because they hijack libc in every C program"
---

# `math.trunc`, `math.log(x, base)`, `math.pow` and `math.copysign` need `pymath_*` intercepts

- **Type:** bug — Track N (`compiler/pyparser.inc`, the `PyStdlibCallProc` table)
- **Opened:** 2026-08-09
- **Filed by:** Track B, doing [[feature-rtl-math-surface-gaps]]. Twelve of the
  sixteen missing names went into `lib/rtl/math.pas` and now match CPython
  exactly. These four cannot: `trunc` and `log` are CONTRACT mismatches — the
  same shape as `math.floor` / `math.ceil`, which already have intercepts a few
  lines above where these belong — and `pow` / `copysign` are blocked by a
  NAME-RESOLUTION bug (section 3).

## 1. `math.trunc` returns a float

CPython:

    math.trunc(-2.5)  ->  -2      (an int)

A Pascal `Trunc(x: Double): Double` in the math unit answers `-2.0`, and the
Python-visible difference is the TYPE, not the value. That is exactly why
`math.floor` and `math.ceil` are intercepted as `pymath_floor` / `pymath_ceil`
rather than resolved against the RTL:

> `math.floor`/`math.ceil` must NOT reach the RTL Math unit's own Floor/Ceil
> (Double->Double, correct for the Pascal frontend, wrong for Python's int
> contract)

`math.trunc` wants `pymath_trunc` beside them, rounding TOWARD ZERO (which is
`floor` only for positives — `trunc(-2.5)` is -2 where `floor(-2.5)` is -3).
Deliberately NOT added to `lib/rtl/math.pas`: a Double->Double `Trunc` there
would resolve ahead of everything and hand every caller the wrong type quietly,
which is worse than the current honest `undefined variable (trunc)`.

## 2. `math.log(x, base)` — the two oracles genuinely disagree

Measured 2026-08-09, all three on this box:

| | `log(1000, 10)` |
| --- | --- |
| CPython `math.log(1000, 10)` | `2.9999999999999996` |
| FPC `LogN(10, 1000)` | `3.00000000000000000` |
| pxx `LogN` (after [[bug-rtl-log10-is-inexact-for-powers-of-ten]]) | `3.0` |

CPython computes `log(x)/log(base)` as a plain quotient and does not snap;
FPC's `LogN` lands exactly on the integer, and pxx's now matches FPC. Note the
argument order differs too (`log(x, base)` vs `LogN(base, x)`), so `math.log`
already needs a shim of some kind.

**Neither implementation is wrong** — each matches its own language's oracle.
That is what an intercept is for: keep `LogN` FPC-faithful for the Pascal
frontend, and give NilPy a `pymath_log` computing CPython's unsnapped quotient.
`math.log10` and `math.log2` need nothing — CPython and FPC agree there, both
exact, and pxx matches both.

Filed as a bug rather than a Track U question because the NilPy rule settles it:
upward compatibility is about a program CPython *accepts and runs*, and ordinary
code branches on this value (`int(math.log(n, 10))` differs by one) — the same
test `devdocs/dev/nilpy-semantics-divergences.md` applies to
`isinstance(t, list)`.

## 3. `pow` and `copysign` cannot live in the Pascal RTL either

Added there, they hijack libc's in every C program —
[[bug-c-pascal-math-names-hijack-libc-through-pxxcio]], measured: `pow(2,10)`
answered 1, `copysign(3,-1)` answered atan2's result. So even though they are
plain float functions with no contract mismatch, an intercept is the only route
that works until that bug is fixed. `Power` and the sign-bit logic are already
in `lib/rtl/math.pas` under non-colliding names for the intercepts to call.

## Gate

`make test-nilpy` green + a `.npy` test whose expectation is CPython's own
output for `math.trunc` on negatives and `math.log(1000, 10)` /
`math.log(8, 2)`.
