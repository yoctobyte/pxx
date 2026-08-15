---
track: B
prio: 45
type: feature
blocked-by: []
summary: "Ln/Exp/Log10/Log2 went 66-107x faster on 2026-08-15; Power and LogN did NOT and are now the two slowest functions in the RTL at ~18-19 s per 1M. Both were left on the double-double log DELIBERATELY: Power amplifies the log's error by |y|, and LogN is a quotient where each rounding lands in the answer. One fix serves both — a fast extra-precision (hi/lo double) log, which is what fdlibm's pow carries instead of calling log."
---

# `Power` and `LogN`: the two that need a fast hi/lo log

- **Type:** feature — **Track B** (`lib/rtl/math.pas`).
- Split out of the fast log/exp work, 2026-08-15. Everything else in the family
  landed; these two are what is left, and they share one cause.

## Where they stand

Per 1M calls, after the fast kernels landed:

| | time | why it did not get faster |
| --- | --- | --- |
| `Ln` | 103 ms | — |
| `Exp` | 121 ms | — |
| `Log10` | 144 ms | — |
| `Log2` | 140 ms | — |
| **`Power`** | **17,977 ms** | still calls `DdLogD` + `DdExpCore` |
| **`LogN`** | **~19,000 ms** | still calls `DdLogD` twice + `DdDiv` |

They are now the slowest things in `lib/rtl/math.pas` by two orders of
magnitude, and `Power` sits under NilPy's `x ** y`.

## Why the fast log is NOT enough for them — do not "just" swap it in

Both were tried and both broke, so the reasons are measured, not predicted:

**`Power`: the error is amplified by the exponent.** `pow(x,y) = exp(y*log x)`,
so an absolute error e in `log x` becomes `|y|*e` in the exponent of `exp`,
which is a RELATIVE error of `|y|*e` in the result. With a 1-ulp log that is
`0.5*|y*log x|` ulp — about 2 ulp at `|y log x| = 4`, and hundreds of ulp for a
large exponent. `Power(1.0001, 10000)` is the row in
`test/lib_math_fast_tolerance.pas` that pins this.

**`LogN`: it is a genuine quotient.** `Log10` and `Log2` can be fast *and* exact
because the exponent extraction hands them the integer part for free (`Log10(10^n)`
is exactly n for n = 0..22, asserted at tolerance 0). An arbitrary base has no
such trick. Measured with `FastLnBits(x) / FastLnBits(base)`:

```
LogN(10,1000)  2.9999999999999996   want 3
LogN(3,81)     4.0000000000000009   want 4
LogN(7,343)    3.0000000000000004   want 3
LogN(10,0.001) -2.9999999999999996  want -3
```

`test/lib_log_exactness.pas` asserts all four are integers and is right to —
that test caught the regression in the lib gate.

## The fix, once, for both

A **fast extra-precision log**: `log(x)` returned as a hi/lo double pair, ~2x
the work of `FastLnBits` rather than the ~100x of `DdLogD` (whose cost is an
18-term dd Horner loop over the un-inlined dd primitives). This is exactly what
fdlibm's `e_pow.c` does — it carries its own `log2(x)` in a `t1`/`t2` hi/lo
split rather than calling `__ieee754_log`, for precisely this reason.

Then:

- `Power`: `y * (hi,lo)` in two-double arithmetic, feed the pair to an `Exp`
  that accepts a hi/lo argument. `FastExpD` already computes its reduction as a
  hi/lo pair internally, so it needs only an entry point that accepts an
  incoming `lo` — a small extension, not a rewrite.
- `LogN`: divide the two hi/lo pairs with one correction step.

Estimated landing point: both in the 200-400 ms range per 1M, i.e. ~50x, with
the exactness properties preserved.

## Do NOT

- Do not make `Power` fast by widening the tolerance on the amplified row. The
  amplification is real and a program computing compound interest or a
  probability product will see it.
- Do not special-case integer exponents to dodge the issue — `IntPower` already
  exists for that and `Power(2.0, 10.0) = 1024` exactly is already asserted.

## Gate

`tools/gate.sh lib` (which includes `lib_log_exactness` — the test that caught
the naive version), `test/lib_math_fast_tolerance.pas` green including the
`power-amplified` and `logn-2-8` rows, `test/lib_math_correctly_rounded.pas`
green under `-dPXX_FLOAT_EXACT`, and a cross-build run under qemu for i386 /
aarch64 / arm32 — the lib gate is x86-64 only and the trig path shipped an i386
segfault that only a qemu run caught.
