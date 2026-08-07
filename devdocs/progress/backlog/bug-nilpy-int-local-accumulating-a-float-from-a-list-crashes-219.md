---
track: N
prio: 55
type: bug
summary: "NilPy: `tot = 0` then `tot += v` over a list holding any float dies with Runtime error 219 (invalid typecast) — averaging a column of mixed ints and floats, ordinary CPython code, crashes"
---

# An int-typed local accumulating a float out of a list crashes with 219

- **Type:** bug (runtime crash on accepted CPython code) — **Track N**
- **Found:** 2026-08-07, bughunting with `tools/pydiff.py`.

## Measured (self-hosted fixedpoint at `8f1852f27`)

```python
vals = [1, 2.5]
tot = 0
for v in vals:
    tot += v
print(tot)
# CPython 3.5
# pxx     Runtime error 219        <- invalid typecast
```

The accumulator's *inferred* type is what decides it, not the data:

| variant | result |
| --- | --- |
| `tot = 0`, list `[1, 2.5]` | **Runtime error 219** |
| `tot = 0`, list `[2.5, 1]` (float first) | **Runtime error 219** |
| `tot = 0.0`, list `[1, 2.5]` | correct, `3.5` |
| `tot = 0`, list `[1, 2]` | correct, `3` |

So `tot = 0` types the local as an int, and the first float element arriving
through the for-in variant fails the cast at runtime rather than widening the
accumulator. Order does not matter — it is not a first-value inference.

`sum(vals)` over the same list is **correct** (`3.5`), which is why a probe that
only uses the builtin misses this; the hand-written accumulate loop is the
shape that breaks, and it is the shape NilPy code actually writes.

## The static form is caught at COMPILE time — only the loop escapes

```python
tot = 0
tot += 2.5
# pascal26:2: error: Nil Python: annotate the type / too dynamic [a=28 b=19]
```

So the int-target/float-source combination is already known to be a problem and
is diagnosed when both types are static. The gap is the path where the source is
a **variant** out of a container: the check does not fire, and it reaches the
runtime cast instead. That is a
`devdocs/dev/normalise-dont-special-case.md` double case — one construct
reachable through a static and a variant shape, with only the static arm
handled.

## Related, and worth reading first

[[bug-nilpy-augmented-assign-of-a-variant-param-to-an-int-field-adds-one]]
(done) is the same family — a variant source augmented-assigned into an
int-typed target — but a **field** target and a silent wrong value (`+= v`
added 1). This one is a **local** target and a hard crash. Whatever fixed the
field path is the first place to look, and the fix should cover both targets
rather than growing a third arm.

## What the right answer is

Widen the accumulator, as CPython does — `int + float` is a float, and the
local's type should follow. Note `tot` is also read after the loop, so the
widening has to be visible to `print(tot)`, i.e. it is the local's inferred type
that must change, not just the one assignment. Failing that, the compile-time
diagnostic above is far better than a 219 at runtime.

## Gate

Per-fix loop. A `.npy` test covering: int accumulator over a mixed list (float
first and last), over an all-int list (must stay int), a float accumulator over
a mixed list, and `sum()` over the same data — diffed against CPython with
`tools/pydiff.py`.
