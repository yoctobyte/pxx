---
track: N
prio: 35
type: bug
blocked-by: []
summary: "abs(-0.0) answers -0.0 (CPython: 0.0) — the sign bit is never cleared — and min()/max() return the LAST of several equal-comparing arguments where CPython returns the FIRST, observable as min(-0.0, 0.0) answering 0.0 instead of -0.0"
---

# abs() keeps the sign of negative zero, and min/max break ties backwards

- **Type:** bug (wrong value, small) — **Track N** (pylib builtins)
- **Found:** 2026-08-12, differential bug hunting against CPython; a
  `-0.0`-focused sweep of the numeric builtins.

| expression | pxx | CPython |
| --- | --- | --- |
| `abs(-0.0)` | **`-0.0`** | `0.0` |
| `min(-0.0, 0.0)` | **`0.0`** | `-0.0` |
| `max(-0.0, 0.0)` | **`0.0`** | `-0.0` |

`abs(-1.5)`, `abs(-3)` and `abs(0.0)` are all correct, so `abs` is not broken in
general: it tests `x < 0`, and `-0.0 < 0` is False, so the negative zero is
returned untouched. Clearing the sign bit unconditionally is both the fix and
the faster instruction.

The min/max rows are one fact, not two: CPython returns the **first** of
several arguments that compare equal (`min` keeps the earliest, and so does
`max`), which is why both answer `-0.0` above. NilPy keeps the last, i.e. its
comparison is `<=`/`>=` where CPython's is `<`/`>`. Negative zero only makes it
*visible*; the case that bites real code is `min(items, key=...)` over
equal-scoring objects, where CPython guarantees the first and NilPy silently
hands back a different object.

## Not the same as the `-0.0` printing question

`str(-0.0)`, `-0.0 * 3` and `float(-0.0)` all agree with CPython already
(`-0.0`), so the representation is right — this is only about these three
builtins.

## Gate

A `.npy` diffed against CPython: `abs` over `-0.0` / `0.0` / negative and
positive floats and ints; `min`/`max` with two equal arguments in both orders,
with a `key=`, over a list, and over objects that compare equal but are
distinguishable (so "returns the first" is actually asserted).
