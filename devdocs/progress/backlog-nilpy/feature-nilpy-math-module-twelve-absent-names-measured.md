---
track: N
prio: 30
type: feature
blocked-by: []
summary: "The whole `math` surface swept name by name against CPython: 39 of 51 agree, 12 are absent and fail LOUDLY at compile. Four of them (isqrt, isfinite, ldexp, frexp) are EXACT operations with no rounding question and can land today; the other eight inherit the standing 'do not map a 1-ulp-off RTL routine' policy."
---

# `math`: the twelve absent names, measured

Swept 2026-08-15, one name per program, `pxx` against CPython — the successor
measurement to [[bug-nilpy-math-surface-remaining-gaps-and-degrees-association]]
and [[bug-n-math-trunc-and-log-need-frontend-intercepts]], which closed the
names they measured.

**39 of 51 agree exactly**, including the ones most likely to have drifted:
`lcm`, `comb`, `perm`, `prod`, `isclose`, `modf`, `fmod`, `degrees`, `radians`,
`hypot`, `copysign`, `factorial`, `gcd`, `trunc`, `log(x)`, `pow`, `sqrt`,
`log2`, `log10`, all six trig/hyperbolic pairs that exist, `pi`, `e`, `tau`,
`inf`, `nan`.

**Twelve are absent.** Every one fails at COMPILE time as `undefined variable`,
so nothing here is a silent wrong answer:

```
isqrt(17)      log1p(0)     expm1(0)     atan2(1,1)
asinh(0)       acosh(1)     atanh(0)     isfinite(1.0)
dist([0,0],[3,4])           remainder(7,3)
ldexp(1,3)     frexp(8)
```

## The split that decides how to land them

**Four are EXACT** — no transcendental, no rounding question, so the standing
policy against mapping a 1-ulp-off RTL routine does not apply and they can be
written in pylib today:

- `isfinite(x)` — `not (isnan(x) or isinf(x))`. A predicate.
- `isqrt(n)` — integer square root, exact by definition; integer math only.
- `ldexp(x, n)` — scaling by a power of two, exactly representable.
- `frexp(x)` — the inverse; returns a PAIR, so it follows `pymath_modf`, which
  already returns a two-element TPyList from a builtin unit.

**Eight inherit the ulp policy** and must not be mapped to an RTL routine until
that routine is correctly rounded — mapping them would trade a loud
`undefined variable` for a silently wrong last digit, which is the trade this
project has refused twice already:

- `atan2` — measured 1 ulp off (`0.46364760900080615` vs `…09`); the note in
  `PyStdlibProcName` says so and keeps it out deliberately.
- `log1p`, `expm1`, `asinh`, `acosh`, `atanh`, `remainder` — same family,
  unmeasured individually. Measure each against CPython BEFORE mapping it;
  agreeing is the only thing that qualifies one.
- `dist` — not a rounding problem but a plumbing one, already recorded in the
  table's comments: it needs `Sqrt` (RTL, unreachable from a builtin unit) over
  pylib CONTAINERS (unnameable from the RTL), so it wants a composed lowering,
  not a table row.

Blocked in the real sense on [[bug-b-rtl-math-transcendentals-lose-argument-reduction]]
and the correctly-rounded-libm work, not on this table.

## Gate

`.npy` diffed against CPython for whichever names land: the four exact ones with
their edge cases (`isqrt(0)`, `isqrt` of a perfect square, `ldexp` denormal and
overflow, `frexp(0)`, `frexp` of a negative, `isfinite` over nan/inf/finite),
and a control that the 39 agreeing names still agree.
