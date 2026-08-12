---
track: N
prio: 35
type: bug
blocked-by: []
summary: "Seven math names still resolve to 'undefined variable' — asin, acos, atan, fsum, modf, perm, dist, prod — and math.degrees(3.14) answers 179.90874767107852 where CPython answers 179.9087476710785, because it computes x*180/pi instead of CPython's x*(180/pi). The `random` module is absent entirely"
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
