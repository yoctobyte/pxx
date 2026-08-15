---
track: B
prio: 45
type: feature
blocked-by: []
summary: "Ln/Exp/Log10/Log2 went 66-107x faster on 2026-08-15; Power and LogN did NOT and are now the two slowest functions in the RTL at ~18-19 s per 1M. Both were left on the double-double log DELIBERATELY: Power amplifies the log's error by |y|, and LogN is a quotient where each rounding lands in the answer. One fix serves both — a fast extra-precision (hi/lo double) log, which is what fdlibm's pow carries instead of calling log."
status: done
owner: claude-B
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

## 2026-08-15 (Track B) — both done. 26x each, and ≤1 ulp everywhere measured

| | before | after | vs 1M calls |
| --- | --- | --- | --- |
| `Power` | 17,977 ms | **690 ms** | 26x |
| `LogN` | ~19,000 ms | **740 ms** | 24x |

(`Ln` is 90 ms on the same box and loop, for scale — these are now within an
order of magnitude of the cheap functions instead of two above them.)

### What landed

Two kernels in `lib/rtl/math.pas`, both fdlibm-shaped and both reusing the
coefficient tables already in the file:

- **`FastLogHiLo(x): TDd`** — the same reduction and polynomial as
  `FastLnBits`, but keeping the bits its final compensated sum throws away.
  `f*f` is taken with `Dd2Prod` so `f - hfsq` is exact, which is where the
  cancellation would otherwise have been, and `k*ln2` rides as a pair because
  `k*ln2hi` is exact. ~2x `FastLnBits`, against `DdLogD`'s ~100x.
- **`FastExpHiLoCore(xh, xl; var k): TDd`** — `FastExpD` already builds its
  reduction as a hi/lo pair internally; the only thing it could not do was
  accept an INCOMING low word, which is exactly what `y*log(x)` hands it. So
  this is that entry point, not a second kernel. It returns a dd so `DdScale`
  can still do its careful subnormal rounding.
- **`FastHiLoQuot(a, b): Double`** — one Newton correction on the double
  quotient with the residual taken exactly. `DdDiv` does that job three times
  over in full dd arithmetic to build a dd result that `LogN` then throws half
  of away; replacing it took LogN from 1.81 s to 0.74 s, i.e. **it was 1.1 of
  the 1.8 seconds.**

`-dPXX_FLOAT_EXACT` is untouched: both functions still take the full
double-double path there, and `lib_math_correctly_rounded` is green.

### The cutover, which is the part that was NOT obvious

Swapping the fast log in and stopping would have been wrong, and measurement is
what said so. `FastLogHiLo`'s accuracy floor is the fdlibm **polynomial**
(~2^-58.4 absolute), not its rounding — so the amplified error GROWS with
|y log x|, which the float policy calls a bug where a flat 1-2 ulp is not.

So the cheap log DECIDES and the expensive one is fetched only where the
decision says it matters: `p.Hi` is `y*log(x)` and is already in hand, so
`if Abs(p.Hi) > 16.0` re-does the log as dd. The threshold is measured, from
11,200 points sweeping |y log x| from 0.5 to 700 over 40 bases, both signs,
judged against glibc:

| cutover | worst ulp by band: 0-4 / 4-16 / 16-32 / 32-64 / 64+ |
| --- | --- |
| 64 | 1 / 1 / 4 / **6** / 1 |
| 32 | 1 / 1 / **4** / 1 / 1 |
| **16** | 1 / 1 / 1 / 1 / 1 |
| 8 | 1 / 1 / 1 / 1 / 1 |

16 is the largest cutover holding 1 ulp everywhere, so it keeps the most of the
range on the fast path; below it nothing improves. The dd log then only fires on
results within a few powers of ten of overflowing, which are not the ones in a
loop.

### Measured accuracy

- `Power`, 11,556 points vs glibc: **worst 1 ulp**, and 1296/1440 exact on the
  amplified sweep. The dd baseline is 0 ulp on all of them, which is the price.
- `LogN`, 900 points vs a **60-digit `decimal` oracle** (not `math.log(x, base)`,
  which is itself a double quotient and would have been testing one
  approximation against another): 898 correctly rounded, worst 1 ulp.
- **Cross-target: bit-identical.** All 11,556 `Power` rows and all 900 `LogN`
  rows produce the same bits under qemu on i386, aarch64 and arm32 as on
  x86-64. The ticket asked for a qemu run because the lib gate is x86-64 only
  and the trig path once shipped an i386 segfault; a differential over the whole
  sweep is a stronger answer than running the suite.

### Regression test

Five `power-amp-*` rows added to `test/lib_math_fast_tolerance.pas` at
tolerance 1, spanning |y log x| = 40 to 292, both signs, with glibc's values.
**Confirmed they bite:** raising the cutover back to 64 makes
`power-amp-58-negative` fail with "6 ulp, tolerance 1". Without them the
cutover could be raised or deleted and every existing row would still pass —
`power-amplified` has |y log x| = 1.0, so it never enters the band it is named
after.

Green on i386/aarch64/arm32 too, and in both float modes.

### Found on the way, and NOT fixed here

This ticket says "`Power` sits under NilPy's `x ** y`". **It does not.**
`pypow_v` carries its own hand-rolled series ln/exp in
`compiler/builtin/pylib.pas` and is out by up to **1282 ulp**
(`1.0001 ** 10000` prints 2.718145926824356 where CPython prints
2.7181459268249255 — wrong in the 12th digit). Filed as
[[bug-a-nilpy-star-star-has-its-own-low-precision-pow]] (Track A: it is
`compiler/builtin`, not `lib/**`). So none of the speed or accuracy above
reaches NilPy yet, and it is worth knowing before anyone credits it there.

### Gate

`tools/gate.sh lib` green; `lib_log_exactness`, `lib_math_fast_tolerance` and
`lib_math_correctly_rounded` (under `-dPXX_FLOAT_EXACT`) green in both float
modes and on all four targets.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
