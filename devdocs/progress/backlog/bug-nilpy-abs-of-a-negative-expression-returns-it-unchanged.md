---
track: N
prio: 45
type: bug
summary: "abs() of a negative INTEGER EXPRESSION returns the value unchanged — abs(0 - i) is -5, not 5"
---

# `abs()` of a negative integer expression returns it unchanged

```python
i = 5
print(abs(0 - i))     # CPython: 5      pxx: -5
print(abs(i))         # CPython: 5      pxx: 5   (correct)
```

Found by the promo output-diff sweep
([[task-n-enumerate-the-promo-surface-by-output-diff]]) and confirmed to be
**independent of promotable ints**: it reproduces with the promotion default
OFF and with a plain `tyInteger` operand, so it is not part of that arc. Filed
separately rather than folded in.

## Why it matters more than the one-liner suggests

`abs()` on an already-positive value is correct, so a test that only checks
`abs(5)` is blind to this. The failing shape is the one that actually appears
in code — a difference, a delta, an error term — and it returns a NEGATIVE
number where Python guarantees a non-negative one. Anything that then compares
against a tolerance (`if abs(a - b) < eps`) silently takes the wrong branch,
which is the "plausible wrong value far from the cause" failure mode, not a
crash.

## Where to look

The `abs` intrinsic's lowering, for whether it is emitting a conditional
negate at all when the argument's static type is an integer EXPRESSION rather
than a simple load. Diff the IR of `abs(i)` against `abs(0 - i)`
(`PXXDBG=a.ir:<proc>`).

## Gate

Per-fix loop. Add a `.npy` test covering `abs()` over a negative expression, a
negative literal, a negative float and a promo — check `ls test/ | grep abs`
first for an existing file to extend.
