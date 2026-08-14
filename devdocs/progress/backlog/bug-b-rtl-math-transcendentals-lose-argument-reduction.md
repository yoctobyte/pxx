---
track: B
prio: 35
type: bug
summary: "lib/rtl/math.pas's sin/cos lose accuracy as the argument grows — 85 ulps at x=100, 1.2 MILLION ulps at 1e6, and 2.4 BILLION at 1e10, where the answer has no correct digits left. Bad argument reduction, not last-bit rounding. pxx's OWN crtl libm already gets every one of these exactly right, so the fix is to share it, not to write one."
---

# The RTL's sin/cos have no usable argument reduction

- **Type:** bug (silent wrong value) — **Track B** (`lib/rtl/math.pas`).
- **Found:** 2026-08-14, sweeping the NilPy `math` surface against CPython while
  landing [[bug-n-math-trunc-and-log-need-frontend-intercepts]]. Affects the
  Pascal frontend identically — it is one RTL unit, and NilPy's `math` module
  resolves straight to it.

## Measured — the error grows with the argument

ulps between `lib/rtl/math.pas` and CPython (which is glibc's libm), same box,
HEAD:

| x | `sin` | `cos` |
| --- | --- | --- |
| 0.5 | 0 | 0 |
| 1 | 0 | 1 |
| 2 | 0 | 1 |
| 3.7 | 0 | 2 |
| 10 | 4 | 3 |
| 100 | **85** | **51** |
| 123.456 | **65** | **87** |
| 1000 | **90** | **131** |
| 1e6 | **1 220 648** | **228 032** |
| 1e10 | **2 461 005 116** | **687 050 531** |

At 1e6 about seven significant digits survive. At 1e10 the result is
uncorrelated with the true value. This is the signature of argument reduction
done in double precision (`x - n*pi` with a rounded pi) rather than against an
extended-precision pi — a known, solved problem (Cody–Waite for moderate
arguments, Payne–Hanek beyond).

**This is not a last-bit ticket.** The small-argument rows (0-2 ulps) are the
ordinary "float handling is low priority" kind. The 1e6 and 1e10 rows are wrong
answers.

## pxx already contains a correct implementation

The same call through pxx's **C** frontend, which uses `lib/crtl`'s libm:

```c
#include <math.h>
printf("%.17g %.17g\n", sin(1e10), sin(123.456));
```

| | sin(1e10) | sin(123.456) |
| --- | --- | --- |
| pxx C frontend (crtl) | `-0.48750602508751067` | `-0.80393736857282394` |
| CPython / glibc | `-0.48750602508751067` | `-0.80393736857282394` |
| **pxx Pascal RTL** | — | `-0.8039373685728312` |

Exact, both rows. So the work is to make `lib/rtl/math.pas` share what
[[project_crtl_libm_correctly_rounded_dd]] already ships, not to implement
reduction from scratch. That is also what would unblock the NilPy `math` names
that are deliberately ABSENT today for exactly this reason.

## The rest of the surface, same sweep

Divergences from CPython on at least one row of {0.5, 1, 2, 0.1, 3.7, 123.456}:

| function | rows differing | worst seen |
| --- | --- | --- |
| `cos` | 4/6 | see table above |
| `tan` | 4/6 | 2 ulps at small x |
| `tanh` | 3/6 | 1 ulp |
| `sin` | 2/6 | see table above |
| `degrees` | 2/6 | 1 ulp |
| `sinh`, `radians` | 1/6 | 1 ulp |

Exact on every row tested: `exp`, `sqrt`, `log`, `log10`, `log2`, `cosh`,
`fabs`, `hypot`, `fmod`, `Power`.

**Inverse trig is inexact too, which is why those NilPy names do not exist.**
`ArcSin(0.5)` is `0.52359877559829915` against CPython's `...893`, `ArcCos(0.5)`
and `ArcTan(0.5)` likewise, and `ArcTan2(0.5, 1)` is
`0.46364760900080615` against `...609`. `math.asin`/`acos`/`atan`/`atan2` are
therefore left as honest `undefined variable` rather than mapped to them —
mapping would ship a silently wrong last bit. They become one-line table entries
the moment this ticket lands (`compiler/pyparser.inc`, `PyStdlibCallProc`).

`ArcSinh(0.5)` and `ArcCosh(1.5)` matched exactly, but on one row each — too
thin to call correct.

## Gate

The ulp table above, re-measured, plus a Pascal and a `.npy` test asserting
CPython's own values for `sin`/`cos` at 100, 1e6 and 1e10. Then the NilPy
inverse-trig names in one follow-up commit.
