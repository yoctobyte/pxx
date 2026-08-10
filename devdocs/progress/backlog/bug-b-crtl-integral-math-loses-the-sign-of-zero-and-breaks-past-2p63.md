---
track: B
prio: 45
type: bug
summary: "crtl's trunc/round/rint/modf/frexp/fabs disagree with gcc on negative zero and on |x| >= 2^63 — fabs(-0.0) answers -0.0, trunc(-0.5) answers +0.0, and trunc(1e300) answers -2^63"
---

# crtl's integral-part math loses the sign of zero, and gives up past 2^63

- **Type:** bug (silent wrong answer, small) — **Track B** (`lib/crtl/src/math.c`)
- **Found:** 2026-08-10, by the full-surface gcc differential written for
  [[bug-c-pascal-math-names-hijack-libc-through-pxxcio]]. **Pre-existing** —
  confirmed by building the same probe with `stable_linux_amd64/default/pinned`,
  which produces the identical set. The math split neither caused nor touched it.

## Measured — gcc `-O1 -lm` as oracle, results compared as raw bit patterns

38 arguments x the whole libm surface. 17 differing results, in three groups:

**1. `fabs(-0.0)` returns -0.0.** C requires +0.0; `fabs` is defined as clearing
the sign bit, and `x < 0.0 ? -x : x` never fires for -0.0 because -0.0 is not
less than zero. One-line fix, and the same shape as the bug already fixed in
`floor`/`ceil` (see their comment: "Sign of zero is OBSERVABLE and C preserves
it" — that lesson has not been applied to the rest of the file).

**2. Negative results that should be -0.0 come back +0.0** — `trunc(-0.5)`,
`rint(-0.5)`, `round(-0.0)`, `frexp(-0.0)`, `modf(-1.0)`'s fractional part and
`modf`'s integral out-parameter for every negative input. All go through a
`(long long)` round trip, which is where the sign dies. `floor`/`ceil` already
restore it explicitly; these did not get the same treatment.

**3. `|x| >= 2^63` is undefined-cast territory.** `trunc(1e300)`, `round(1e300)`
and `modf(1e300)` answer -2^63 (0xc3e0000000000000) where gcc returns the input
unchanged — every double that large is already an integer. `floor`/`ceil` guard
this with an explicit `|x| >= 2^52` early return; `trunc`, `round` and `modf` do
not, and `trunc`'s own comment concedes it ("|x| >= 2^63 is out of scope, like
the other loop-form helpers here"). It should not be out of scope: the guard is
one comparison and the answer is the argument.

## Why it is filed low

Every case is a boundary value, none is a crash, and -0.0 is observable only
through printing or a sign-bit test. But group 3 is a wrong *magnitude*, not a
wrong sign, and all three are cheap: `floor`/`ceil` already carry both fixes and
can simply be copied down the file. Do all six together — this is one bug wearing
six hats (see `normalise-dont-special-case.md`), and fixing one at a time is how
the other five stay broken.

## Not in scope here

The differential's other 131 differing results are `asin`/`acos`/`atan2`/`cbrt`/
`log10`/`hypot`/`sinh`/`cosh`/`tanh`/`pow`. Those are the correctly-rounded
double-double kernels, where a difference from glibc is often glibc misrounding
(the file header documents measured misround rates: cbrt ~55% of arguments).
They need a decimal reference, not gcc, to judge — a separate, bigger job.

## Gate

The probe (see the parent ticket) showing zero `trunc`/`round`/`rint`/`modf`/
`frexp`/`fabs` differences against gcc, plus `make lib-test` and the C suites.
