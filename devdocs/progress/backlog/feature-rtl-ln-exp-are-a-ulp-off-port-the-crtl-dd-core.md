---
summary: "lib/rtl's Ln/Exp are plain-double series and land ~1 ulp off; lib/crtl already has a correctly-rounded double-double log/exp core, so the Pascal RTL is the second, worse mechanism for the same concept"
track: B
prio: 35
type: feature
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
