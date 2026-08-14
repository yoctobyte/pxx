---
track: N
prio: 35
type: bug
blocked-by: []
summary: "Seven math names still resolve to 'undefined variable' — asin, acos, atan, fsum, modf, perm, dist, prod — and math.degrees(3.14) answers 179.90874767107852 where CPython answers 179.9087476710785, because it computes x*180/pi instead of CPython's x*(180/pi). The `random` module is absent entirely"
status: done
owner: agent-AN
---

# math: the remaining missing names, and `degrees()` associates the wrong way

- **Type:** bug (missing surface + last-ulp divergence) — **Track N**
- **Found:** 2026-08-12, sweeping the whole `math` surface against CPython.
- **Companion to** [[bug-n-math-trunc-and-log-need-frontend-intercepts]], which
  covers `trunc` / `log` / `pow` / `copysign` / `atan2`. This is what a full
  sweep found *besides* those.

## 1. `degrees()` — a real value divergence, one line to fix

```
math.degrees(3.14)   pxx: 179.90874767107852   CPython: 179.9087476710785
```

Measured directly: pxx's answer is exactly `3.14 * 180 / math.pi` and CPython's
is exactly `3.14 * (180 / math.pi)`. The conversion factor must be formed
FIRST and then multiplied — the same constant CPython uses — rather than
multiplying by 180 and dividing by pi. `radians()` agrees already, so only
`degrees` is wrong.

## 2. Names that do not resolve at all

Each is `error: undefined variable`:

| name | CPython |
| --- | --- |
| `math.asin(0)` | `0.0` |
| `math.acos(1)` | `0.0` |
| `math.atan(1)` | `0.7853981633974483` |
| `math.fsum([...])` | exact compensated sum |
| `math.modf(2.5)` | `(0.5, 2.0)` |
| `math.perm(5, 2)` | `20` |
| `math.dist([0,0], [3,4])` | `5.0` |
| `math.prod([1,2,3])` | `6` |

`sin`/`cos`/`tan`/`hypot`/`comb`/`gcd`/`factorial`/`isclose`/`fmod`/`copysign`
/`log2`/`log10`/`exp`/`sqrt`/`floor`/`ceil`/`inf`/`nan`/`pi`/`e` are all present
and agree, so this is a short tail rather than a hole.

`fsum` is worth doing together with
[[bug-nilpy-sum-of-floats-has-no-compensated-summation]] — same algorithm,
two callers.

## 3. `import random` does not exist

`random.random()` / `random.randint()` / `random.seed()` are all "undefined
variable". Not a divergence so much as an absent module, but it is one of the
first imports a script reaches for, and seeding makes it testable against
CPython only for the *shape* (a float in [0,1), an int in range) — the sequence
itself is deliberately implementation-defined, so the gate must assert the
contract, not the values.

## Gate

A `.npy` diffed against CPython: `degrees` over several angles (including the
row above, which is what shows the association), every name in the table with a
value CPython pins exactly, and — if `random` lands here rather than in its own
ticket — range/type assertions plus `seed()` making two runs of the same program
agree with each other.

## Resolution (2026-08-15)

All three sections done, with one deliberate exclusion.

**1. `degrees()`** — `lib/rtl/math.pas` now forms the conversion FACTOR first
(`r * (180/pi)`, and `d * (pi/180)` for the sibling), which is how both CPython
and FPC associate it. `math.degrees(3.14)` is `179.9087476710785`. The fix
lands in a Track B file because that is where `RadToDeg` lives; it is two lines,
additive to nothing, and it corrects the PASCAL frontend's FPC parity by the
same edit.

**2. The eight missing names — seven landed, one refused for a stated reason.**

- `asin`/`acos`/`atan` were a pure NAME difference: the RTL spells them
  `ArcSin`/`ArcCos`/`ArcTan`, so three rows in the intercept table is the whole
  change — exactly what `math.log` -> `Ln` already does.
- `modf`, `prod`, `fsum`, `perm` are new pylib routines. None needs a
  transcendental, which is precisely what lets them live in a BUILTIN unit (the
  wall `math.log`/`math.pow` hit). `fsum` is Neumaier compensated summation and
  should be SHARED with `sum()` when
  [[bug-nilpy-sum-of-floats-has-no-compensated-summation]] lands, not copied.
- **`dist` is NOT done, and this is the interesting one.** It needs `Sqrt`,
  which lives in `lib/rtl/math.pas` and a builtin unit cannot reach, while its
  arguments are pylib CONTAINERS the RTL cannot name. It is the one entry that
  needs a composed lowering rather than a table row, so it is left out with a
  comment at the table saying why, rather than half-built.

Two things the CPython diff caught that reasoning would not have:

- `math.modf(-0.25)` is `(-0.25, -0.0)` — the integral part keeps the sign even
  when it is ZERO, and `Int()` hands back a positive zero. Read from the sign
  BIT, like `copysign` does.
- `asin`/`acos` are 1-2 ulps off libm for mid-range arguments while `atan` and
  the endpoints are exact — an accuracy defect in the RTL, not in the wiring.
  Filed as [[bug-b-arcsin-arccos-lose-2-ulps-vs-libm]] (Track B, p20); this
  test asserts only the exact cases until it lands.

**3. `random` exists now** — `seed`, `random`, `randint`, `randrange`,
`uniform`, `choice`, `shuffle`, on pylib's own SplitMix64. The sequence is
deliberately not CPython's (its Mersenne stream is an implementation detail
there too), so the test asserts the CONTRACT: `random()` in [0, 1),
`randint(a, b)` inclusive at both ends, a repeated seed repeating, `choice()`
an element of the sequence, `shuffle()` a permutation that mutates in place and
returns None. The state starts at a FIXED value rather than a clock reading, so
a program that never seeds still reproduces — which is what makes a failure
reportable.

**Gate:** `test/test_nilpy_math_surface_and_random.npy` (+`.expected`, wired
into the Makefile). The math half is byte-identical to CPython; the random half
asserts the contract. `tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-15 — resolved, commit 3799e1d77.
