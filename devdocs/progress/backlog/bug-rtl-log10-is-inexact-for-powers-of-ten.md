---
track: B
prio: 55
type: bug
---

# `Log10` is inexact for powers of ten — `int(log10(n))` is off by one

```python
import math
for n in [1, 10, 100, 1000, 10000, 100000, 1000000]:
    print(n, math.log10(n), int(math.log10(n)))
```

| n | CPython | pxx |
| --- | --- | --- |
| 10 | `1.0` → 1 | `0.9999999999999998` → **0** |
| 100 | `2.0` → 2 | `1.9999999999999996` → **1** |
| 1000 | `3.0` → 3 | `2.9999999999999996` → **2** |
| 10000 | `4.0` → 4 | `3.999999999999999` → **3** |
| 100000 | `5.0` → 5 | `5.0` → 5 (correct by luck) |
| 1000000 | `6.0` → 6 | `5.999999999999999` → **5** |

**Silent, and it breaks the standard digit-count idiom.** `int(math.log10(n)) + 1`
is how everyone counts digits; here it is wrong for almost every power of ten,
and *right* for 100000, so a spot check can pass. Nothing raises — the value is a
plausible float a hair below the integer.

## Cause

`lib/rtl/math.pas`:

```pascal
function Log10(x: Double): Double;
begin
  Result := Ln(x) / 2.30258509299404568402;
end;
```

`Ln` is a series expansion, and dividing its result by ln(10) lands just below
the integer for exact powers of ten. A correctly-rounded `log10` (what libm and
therefore CPython give) returns the integer exactly.

`Log2` and `LogN` are the same shape and want checking together — `log2(8)`
happens to come out exactly 3.0 today, which is luck, not correctness.

## Suggested fix

The cheap, well-founded one: compute as now, round the result to the nearest
integer `k`, and if `10^k` reproduces `x` exactly (integer power comparison, in
the representable range) return `k` as an exact float. That makes every exact
power of ten exact — the cases that matter and the cases that are checkable —
without changing any other value. Same treatment for `Log2` with `2^k`, where
the check is exact for the whole double range.

Improving `Ln`'s accuracy generally would be better still but is a bigger job;
the exactness fix stands on its own.

## Also found, same sweep, much lower impact

`math.exp(1)` = `2.7182818284590446` against CPython's `2.718281828459045` —
1 ulp. Worth a note next to `Exp`, not worth its own ticket.

## Found by

Sweeping the numeric/`math` surface against CPython. Everything else measured
correct: `//`, `%` and `divmod` with negative operands, `round` half-to-even,
`int()`/`float()` conversions, `**` including negative and fractional exponents,
bit operators, big-int literals, `bin`/`oct`/`hex`, `math.pi`, `sqrt`, `sin`,
`cos`, `gcd`, `fabs`, `hypot`, `fmod`, `floor`, `ceil`, `log2`.

## Gate

`make lib-test` + a test asserting `math.log10` and `int(math.log10(n))` for
every power of ten from 1 to 1e15, `log2` for every power of two in range, and
a handful of non-power values against CPython.
