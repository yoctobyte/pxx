---
summary: "lib/rtl's Ln/Exp are plain-double series and land ~1 ulp off; lib/crtl already has a correctly-rounded double-double log/exp core, so the Pascal RTL is the second, worse mechanism for the same concept"
track: B
prio: 35
type: feature
status: done
owner: claude-B
---

# `lib/rtl` math is a ulp off, and the good implementation already exists in `lib/crtl`

## The measurement

Against CPython (which is libm), on `master` after
[[bug-rtl-log10-is-inexact-for-powers-of-ten]]:

| expression | CPython / libm | pxx `lib/rtl` |
| --- | --- | --- |
| `log10(2)` | `0.3010299956639812` | `0.30102999566398114` |
| `log10(7)` | `0.8450980400142568` | `0.8450980400142566` |
| `log2(3)` | `1.584962500721156` | `1.5849625007211563` |
| `log10(0.3)` | `-0.5228787452803376` | `-0.5228787452803375` |
| `exp(1)` | `2.718281828459045` | `2.7182818284590446` |

One ulp, everywhere, on every value that is not a snapped exact power. It is
inherited by `Log10`/`Log2`/`LogN`/`Power` — everything that goes through `Ln`.

## Two mechanisms for one concept

`lib/rtl/math.pas` `Ln` is an atanh series accumulated in plain doubles, with
`e * ln2` added using a single-double `ln2` constant: ~50 roundings in the sum
plus a rounded constant scaled by up to 1023 — a ulp is exactly what that buys.

`lib/crtl/src/math.c` already does it properly for C: `crtl_log_ddx` normalizes
to `[sqrt2/2, sqrt2)`, runs 18 odd terms of the same atanh series in
**double-double** (~2^-88), and adds `e * ln2` as a dd constant; `__crtl_log2` /
`__crtl_log10` then multiply by a dd `1/ln2` / `1/ln10`. That is correctly
rounded, and it gets the exact cases (`log2(2^n) = n`) for free, structurally —
no snapping. Same for `crtl_exp_dd`. It is covered by
`test/cmath_log_correct_round_b378.c` and `cmath_exp_correct_round_b377.c`.

So the repo has the algorithm; the Pascal RTL just does not use it. Per
`devdocs/dev/normalise-dont-special-case.md` that is the smell — and libraries in
this repo are supposed to be split by *what they do*, never by source language.

## The work

Port the dd core to `lib/rtl`: a small `Dd` record (`hi`, `lo`) with two-sum,
Dekker two-product (or FMA where the backend has it), add/mul/div, then `Ln`,
`Exp`, and the `Log10`/`Log2`/`LogN` wrappers on top of it. `Power` and the
hyperbolics fall out.

When that lands, **delete `SnapLog` from `lib/rtl/math.pas`** — it exists only
because the current `Ln` cannot hit the integer, and a correctly-rounded dd log
does. `test/lib_log_exactness.pas` is the regression test either way and must
stay green across the swap.

## Why it is not urgent

Nothing observed is *wrong*, only last-bit inexact, and the case that actually
broke user-visible behaviour (`Trunc(Log10(n))` for powers of ten) is fixed. So
this is quality, not a bug — but it is the root cause the snap works around, and
it removes a special case rather than adding one.

## Gate

Track B: `tools/gate.sh lib`, plus a differential run of the numeric surface
against CPython (`tools/pydiff.py`) showing the ulp column gone.

## Resolution 2026-08-09 (Track B) — ported, and it beat the oracle

`lib/rtl/math.pas` now runs `Ln`, `Log10`, `Log2`, `LogN`, `Exp` and `Power` on
a double-double kernel ported from `lib/crtl/src/math.c`: `TDd`, the error-free
transformations (fast2sum / 2sum / Dekker 2prod), dd add/mul/div, `DdLogD`,
`DdExpCore`, `DdScale` (including the integral subnormal rebuild), plus `Ldexp`
and a ties-to-even `Rint` the C version got from libm. Constants come from bit
patterns, as in the C original.

**`SnapLog` is deleted**, which was this ticket's stated test of success. The
exact cases now fall out structurally — for x = base^k the series contributes
zero and the answer is k*ln(base) carried to ~106 bits — so
`test/lib_log_exactness.pas` (400 assertions) passes unchanged across the swap.
That test pinned the behaviour, not the mechanism, which is exactly what let the
special case be removed rather than kept beside the fix.

### Measured on the BITS, not on printed digits

A first attempt compared `writeln(x:0:17)` output and was useless: our float
formatter and CPython's `repr` differ, so the digits measured the formatter as
much as the function. Comparing raw IEEE bit patterns instead, over a
1300-value random sweep:

| | vs glibc |
| --- | --- |
| `Ln` | **1300 / 1300 bit-identical** |
| `Log2` | **1300 / 1300 bit-identical** |
| `Log10` | 1228 identical, 72 differing by exactly 1 ulp |

The 72 were then checked against a THIRD source — 60-digit `Decimal` — and in
**all 72 pxx is the correctly rounded answer and glibc is the one that is
wrong**. glibc's `log10` is not a correctly-rounded routine while its `log`,
`log2`, `exp` and `pow` are, so for `log10` the oracle has to be arbitrary
precision. Six of those cases are pinned in the new test with a note not to
"fix" them toward CPython.

`Exp` is bit-identical to glibc on all 20 probe values including the subnormal
tail (`Exp(-745)`), and `Power` on all four, having been 1 ulp off on three of
them before.

### Two bugs found on the way, both in Power

`Power` was `Exp(exponent * Ln(base))` with `if base <= 0.0 then Result := 0.0`,
so it answered **0.0 for every non-positive base**. IEEE says `(-2)^3 = -8`,
`0^0 = 1`, and a negative base with a fractional exponent is a domain error
(NaN) — three wrong answers, silently. The port brings the full edge-case
ladder over from crtl's `pow`, and the new test pins each.

### Gate

`tools/gate.sh lib` GREEN. New `test/lib_math_correctly_rounded.pas` asserts the
bit patterns; `lib_log_exactness` and `lib_math_python_surface` unchanged and
still green.


## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
