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

## The table's COMMENT has gone stale, and it gives atan2 the wrong reason

Measured 2026-09-08 (`compiler/pascal26` a7b03135f504), reaching this ticket from
the lekkerzeilen target, whose `hud.py` wants `math.atan2`.

The comment above the `math.*` mapping table in `compiler/pyparser.inc` says:

> `math.log / math.pow / math.atan2` are NOT here — they need a transcendental
> (Ln, a correctly-rounded pow) and a BUILTIN unit cannot reach one

**Two of the three named now work**, and so does the function that most directly
refutes the stated reason:

| | pxx | CPython |
| --- | --- | --- |
| `math.log(2.718281828)` | 0.9999999998311266 | identical |
| `math.pow(2.0, 10.0)` | 1024.0 | identical |
| `math.hypot(3.0, 4.0)` | 5.0 | identical |

`hypot` needs `Sqrt`, so "a builtin unit cannot reach the RTL" is not what keeps
`atan2` out **today** — the ULP POLICY above is, and that is a completely
different reason with a completely different fix.

**This misroutes, and it misrouted this seat.** Reading only the comment, the
obvious conclusion is that `atan2` needs a lowering redesign, and the obvious
cheap fix is a table row — `lib/rtl/math.pas:63` already declares
`function ArcTan2(y, x: Double): Double` and the rows just below resolve
`math.asin` -> `ArcSin` by exactly that rename. **That fix is the one this
project has refused twice**, and it would ship a silently wrong last digit in
place of a loud `undefined variable`. The comment should name the ulp policy and
point here; it currently names a reachability wall that three working functions
disprove.

**A note for a caller that does not need the last digit:** the refusal is a
GLOBAL policy about what `math.atan2` may silently mean, not a claim that no
program may use `ArcTan2`. A target permitted to change its own source (see
[[umbrella-lekkerzeilen-compiles-and-runs-under-nilpy]], where the owner has
licensed exactly that) can call an explicit helper and carry the 1 ulp knowingly
— a HUD heading does not care. Do not read this as licence to map the name.

---

## `atan2` alone is the largest single blocker on the lekkerzeilen umbrella (2026-09-09)

Measured over `lekkerzeilen/*.py`, first error only: `math.atan2` is the first
failure in **five of the twenty-three modules** — hud, rig, sim, traffic,
vessel — which is more than any other cause, ahead of the closed-world dispatch
fork (4) and `import array` (3). The umbrella is owner-directed at prio 75, so
this ticket's effective prio already inherits that; what the body did not say
is that ONE of the twelve names carries almost all of it.

That does not by itself overturn the split above — `atan2` is in the eight that
inherit the do-not-map-a-1-ulp-off-routine policy, and this is a ranking fact,
not an accuracy argument. It is recorded because whoever picks this up should
know that landing `atan2` and nothing else is worth five modules, and that the
question to settle first is the policy one, not the implementation.

Beside it, for whoever sweeps this again: `math` here resolves far enough to
report `no member atan2 came of the qualifier math`, i.e. the import bound
something. That is the loud-at-compile behaviour the sweep claimed, re-observed
25 days later on real source.
