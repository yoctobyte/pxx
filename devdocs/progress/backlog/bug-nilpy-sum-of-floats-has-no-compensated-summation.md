---
track: N
prio: 45
type: bug
blocked-by: []
summary: "CPython's builtin sum() uses Neumaier compensated summation for floats; NilPy's adds naively, so sum([1e16, 1.0, -1e16]) answers 0.0 where CPython answers 1.0, and sum([0.1]*10) answers 0.9999999999999999 where CPython answers 1.0. Ordinary averaging code disagrees with the oracle in the last digits, or loses a whole term"
---

# sum() of floats has no compensated summation

- **Type:** bug (silent wrong value — accuracy) — **Track N** (pylib builtin)
- **Found:** 2026-08-12, differential bug hunting against CPython.

CPython's `sum()` has used **Neumaier compensated summation** for float inputs
since 3.12. NilPy adds term by term, so the results differ:

| expression | pxx | CPython |
| --- | --- | --- |
| `sum([0.1, 0.2, 0.3])` | `0.6000000000000001` | `0.6` |
| `sum([0.1] * 10)` | `0.9999999999999999` | `1.0` |
| `sum([1e16, 1.0, -1e16])` | **`0.0`** | `1.0` |

The last row is the one that matters: the `1.0` is not rounded away, it is
**dropped entirely** — a naive accumulator loses it against the 1e16 term and
never gets it back. Compensated summation is precisely the fix for that, which
is why CPython adopted it.

Int sums are unaffected (`sum([1, 2, 3])` = 6, exact by construction), and so
is the empty sum (`0`).

## Why this rates a ticket rather than a divergence note

Two reasons it is not "floats are just like that":

1. **CPython is the specified oracle.** NilPy is upward compatible with
   CPython, and this is code CPython accepts and runs — an average, a total, a
   weighted score — answering differently in the last digit, or by a whole term.
2. It is **cheap to match**: Neumaier is a running compensation term added to
   the existing loop, not a new algorithm.

## Implementation

The float arm of the `sum` builtin in pylib. Neumaier (the variant CPython
uses, which handles the case where the running total is smaller than the term):

```
t = s + x
if abs(s) >= abs(x): c += (s - t) + x
else:                c += (x - t) + s
s = t
...
return s + c
```

Guard the arms the same way CPython does: an all-int sum stays exact-int (NilPy
ints are arbitrary precision, so it must not be routed through the float path),
and the compensation only applies once the accumulator has actually become a
float.

## Gate

A `.npy` diffed against CPython: the three rows above, an int-only sum, a mixed
int/float sum, an empty sum, a sum with a `start` argument, and a sum over a
generator/comprehension — plus `math.fsum` if it exists, which must agree too.
