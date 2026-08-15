---
track: B
prio: 35
type: bug
summary: "lib/rtl/math.pas's sin/cos lose accuracy as the argument grows — 85 ulps at x=100, 1.2 MILLION ulps at 1e6, and 2.4 BILLION at 1e10, where the answer has no correct digits left. Bad argument reduction, not last-bit rounding. pxx's OWN crtl libm already gets every one of these exactly right, so the fix is to share it, not to write one."
status: done
owner: track-b-bughunt
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

## Resolution (2026-08-15) — the reduction ported from crtl

`Sin`, `Cos` and `Tan` now use `lib/crtl/src/math.c`'s argument reduction:
Cody-Waite with pi/2 in three 24-bit chunks plus a dd tail for |x| < 1e8, and
Payne-Hanek against a 1440-bit 2/pi expansion beyond it, with dd Taylor kernels
on the reduced argument. Third time this file has replaced a plain-double
mechanism with the crtl dd one instead of patching it (after Ln/Exp, and after
the inverse trig earlier the same day).

### The old line had TWO defects, not one

```pascal
k := Trunc(x / 6.28318530717958647692);   { <- Integer, not Int64 }
r := x - k * 6.28318530717958647692;      { <- a ROUNDED 2pi }
```

The rounded 2pi is the one the ticket describes. The second is that `k` is a
32-bit **Integer**, so the reduction silently overflowed past x ~ 1.3e10 —
which is why the 1e10 row was not merely inaccurate but uncorrelated.

### Every row of the ticket's table is now exact

sin/cos/tan at 0.5, 1, 2, 3.7, 10, 100, 123.456, 1000, 1e6 and 1e10: **0 ulp
against glibc on all thirty**. The 1e6 row was 1,220,648 ulp and the 1e10 row
2,461,005,116.

### Wider sweep, and we are now BETTER than glibc

11,000 arguments (random small, random to 1e6, random up to 2^1023, and every
double within 2 ulp of the first 400 multiples of pi/2): sin and cos differ
from glibc on ~10 values each, tan on 36, almost all by 1 ulp. Arbitrated
against 400-digit arithmetic on a 337-value subsample:

```
sin: pxx 0/337 wrong,  glibc 3/337
cos: pxx 0/337 wrong,  glibc 2/337
tan: pxx 0/337 wrong,  glibc 6/337
```

The worst disagreement in the whole sweep — `cos(5.319372648326541e255)`, 8 ulp,
and `tan` of the same argument, 14 ulp — is **glibc's error, not ours**: that
argument sits very close to an odd multiple of pi/2, which is precisely what
Payne-Hanek is for, and the 400-digit value agrees with us to the last bit.

Special values match CPython bit for bit: `Sin(-0)` is `-0`, `Cos(-0)` is 1,
`Tan(-0)` is `-0`, and all three give NaN for +-Inf and NaN.

### A Track A bug fell out of it

`Sin(1e20)` came back NaN on i386 and arm32 while x86-64, aarch64 and riscv32
were green. Cause: **`Int(x)` saturates to 32 bits on those two backends** —
`Int(2^43 + 0.5)` is `-2147483648.0` on i386 and `2147483647.0` on arm32, where
`Trunc` of the same value is right everywhere and riscv32 (also 32-bit) is
right too. Filed as
[[bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32]] (prio 55,
silent wrong value in a builtin).

`DdFloor` and `DdRint` use `Double(Trunc(x))` until that lands, registered in
`devdocs/dev/track-b-workarounds.md` with `Int(x)` as the revert target.
`DdRint`'s callers all stay under 2^31 today, so nothing there was observably
wrong — that half was latent, and is now closed too.

Verified under qemu on i386, aarch64 and arm32 as well as natively.

### The cost, stated rather than buried

1M `Sin`+`Cos` pairs: **673 ms before, 29,383 ms after** — 44x. Two
measurements put that in context before anyone reads it as a regression to
revert:

- The same dd algorithm through pxx's **C** frontend is 41,174 ms, i.e. *slower*
  than this Pascal port. It is the algorithm's price, not a codegen problem.
- The already-shipped, already-blessed `Ln`+`Exp` cost 16,480 ms per 1M pairs
  against glibc's 13 ms — **1270x**. So this file's standard is already
  correctness-over-speed, and these functions now match it rather than deviating
  from it.

Nothing in this tree calls trig per-pixel (`vecmath` builds a rotation matrix,
the raytracer and GL demos set a camera or animation angle once per frame), so
29 us a call lands nowhere hot today. Whether the RTL should grow a *fast* tier
beside the correct one is a policy question above this ticket, and is filed as
[[decide-rtl-math-correctly-rounded-vs-fast-tier]] with the numbers and a
recommendation.

### The ticket's other half was already done

The inverse-trig paragraph is stale as of earlier today:
[[bug-b-arcsin-arccos-lose-2-ulps-vs-libm]] is resolved, and NilPy's
`math.asin`/`acos`/`atan` already exist and are asserted mid-range in
`test/test_nilpy_math_surface_and_random.npy`. No follow-up commit is needed
for those names.

Test: `test/lib_math_correctly_rounded.pas` gains 15 rows at 100, 123.456,
1000, 1e6, 1e10 and 1e100 — the last exercising the Payne-Hanek path rather
than Cody-Waite.

## Log
- 2026-08-15 — resolved, commit dc60b64fb.
