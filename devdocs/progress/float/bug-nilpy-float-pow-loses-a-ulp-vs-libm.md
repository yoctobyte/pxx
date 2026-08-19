---
prio: 20
track: N+F
type: bug
blocked-by: []
---

# `2 ** 0.5` is not `math.sqrt(2)` — the float power is computed as exp(y·ln x)

- **Type:** bug (NilPy, **silent precision loss**) — **Track N**
- **Found:** 2026-08-09, same numeric sweep that found
  [[bug-nilpy-pow-and-log-hang-on-a-non-positive-base]]
- **Owner:** —

## Measured

```python
import math
a = 2 ** 0.5
print(a)                    # CPython 1.4142135623730951   pxx 1.414213562373095
print(a == math.sqrt(2))    # CPython True                 pxx False
print(a * a)                # CPython 2.0000000000000004   pxx 1.9999999999999996
print(2 ** 1.5)             # CPython 2.8284271247461903   pxx 2.8284271247461894
```

`math.sqrt(2)` itself is **correct** (`1.4142135623730951`), so the error is in
the power path, not in the float printer — and the two disagree with each other,
which is the sharper symptom: within one program `x ** 0.5` and `math.sqrt(x)`
answer differently.

Not every input is wrong: `3 ** 0.5` and `10 ** 0.5` match CPython exactly. So
this is a last-ulp error on some inputs, not a systematically bad algorithm.

## Cause

`pypow_v`'s fractional-exponent arm is

```pascal
fr := PyMathExp(fexp * PyMathLn(fbase));
```

`exp(y·ln x)` loses precision twice — once in `ln`, once amplified by `exp` —
where a real `pow` keeps extra bits through the multiply. `PyMathLn` is a
40-term atanh series plus `e * Ln2`, and `PyMathExp` a 25-term Taylor plus
repeated doubling; each is close, and the composition is not.

## Why it matters despite being one ulp

Silent, and it breaks an INVARIANT rather than just a digit: `x ** 0.5 ==
math.sqrt(x)` is False, so a program that computes a value one way and compares
it with the other takes the wrong branch. Accumulated over an iteration it
drifts further (`a * a` is already 4 ulp from 2.0 and on the wrong SIDE of it).

## Shape of a fix

Do not hand-roll another series. Options, cheapest first:

1. **Route to the platform `pow`** if one is reachable from `pylib` — the crtl
   libm is documented as correctly rounded
   ([[project_crtl_libm_correctly_rounded_dd]]); check whether it is linkable
   here or whether that is C-side only.
2. **Use exp2/log2 with a two-part (double-double) product** for `y·log2 x`,
   which is the standard way to keep the extra bits `exp(y·ln x)` throws away.
3. **Special-case the exponents that matter** (`0.5` -> sqrt, `1/3`, integer +
   0.5) — cheap, and dishonest as a general answer; only worth it as a stopgap
   for `** 0.5`, which is the one people actually write.

Prefer 1 if it links, else 2. Note the same `PyMathLn`/`PyMathExp` pair backs
anything else built on them, so an improvement there is shared.

## Gate
`.npy` diffed against CPython: `x ** 0.5` vs `math.sqrt(x)` for a range of x
(equality, not just printing), `2 ** 1.5`, `x ** (1/3)`, and a loop that squares
a root back and checks it stays on CPython's side of the true value.


## Priority — float handling is parked low (user, 2026-08-14)

> *"bugs related to float handling have low prio atm. they are mechanical, and do
> not impact the compiler, and are for track B"*

Re-rated from 35 to 20 on that call. The defect itself is unchanged and the write-up
below stands — this is a ranking decision, not a downgrade of the finding. Same
judgement the user already applied to float PERFORMANCE work in
`feature-opt-float-register-temporaries` (prio 20, 2026-07-19), now extended from
speed to accuracy.

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.
