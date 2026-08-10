---
track: B
prio: 45
type: bug
summary: "crtl's trunc/round/rint/modf/frexp/fabs disagree with gcc on negative zero and on |x| >= 2^63 — fabs(-0.0) answers -0.0, trunc(-0.5) answers +0.0, and trunc(1e300) answers -2^63"
status: done
owner: trackB
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

## 2026-08-10 (Track B): fixed, all six together

Done as one change, per the ticket's own "one bug wearing six hats" call — the
two corrections `floor`/`ceil` already carried were copied down the file rather
than each function getting its own variant.

| function | was | now |
| --- | --- | --- |
| `fabs` | `x < 0.0 ? -x : x` — misses -0.0, which is not `< 0.0` | tests the sign BIT (`crtl_signbit_d`), which is fabs's actual definition |
| `trunc` | bare `(long long)` cast | `\|x\| >= 2^52` early return + -0.0 restore |
| `round` | `(long long)(x +/- 0.5)` | fraction compare vs 0.5, same guard + restore |
| `rint` | returned the neighbour's zero | same guard + restore |
| `frexp` | `return 0.0` for zero; **hung** on infinity | returns `x`; NaN/inf exit early |
| `modf` | cast through `long`, rebuilt sign by negating | rides `trunc()`, so it inherits both fixes and has no range logic of its own |

Normalised on **2^52**, not the 2^63 the ticket named: it is the threshold
`floor`/`ceil` already use, every double at or above it is integral, and one
threshold across the family is one fewer thing to get inconsistent.

### Two things found that the ticket did not list

**`frexp(1.0/0.0` HUNG** — not a wrong value, a non-terminating loop:
`while (a >= 1.0) a = a * 0.5` never converges for an infinity. Measured both
ways, since a hang is easy to assert and easy to get wrong: the pre-fix build
times out at 5s, the fixed build returns `inf` immediately. The differential
probe could not have caught this — it skips infinity for `frexp` — so it would
have survived the ticket's own gate.

**`round(0.49999999999999994)` answered 1, C requires 0.** A separate bug in the
same function and unrelated to sign or range: the old body cast `x + 0.5`, and
for the double just below 0.5 that sum rounds UP to exactly 1.0. Comparing
against `x - trunc(x)` never adds and so cannot round.

### Verification

- **gcc `-O1 -lm` as oracle**, 22 arguments x 8 functions = **216 results,
  bit-for-bit identical**. Confirmed the probe is not blind by rebuilding
  against the pre-fix file: **31 differing lines before, 0 after**.
- **i386 cross-build run natively: identical to the same gcc oracle**, all 216.
  Checked because `gate.sh lib` is x86-64 only while `lib/crtl` builds for every
  target — the exact gap that shipped a past i386 regression
  ([[crtl-changes-need-a-cross-check]]). aarch64 / arm32 / riscv32 compile clean
  (not run — no runner here).
- **Regression test**: `test/cmath_integral_family.c`, wired into `lib-test`,
  expectations are gcc's own output. The `frexp(inf)` row is a LIVENESS check —
  a regression there hangs the target rather than mismatching, which is called
  out at both the test and the Makefile so nobody reads a timeout as flake.

Out of scope as filed: the 131 `asin`/`acos`/`atan2`/`cbrt`/`log10`/`hypot`/
`sinh`/`cosh`/`tanh`/`pow` differences are the correctly-rounded double-double
kernels, where a gcc difference is often glibc misrounding. Those need a decimal
reference, not gcc.

## Log
- 2026-08-10 — resolved, commit 9f941deb1.
