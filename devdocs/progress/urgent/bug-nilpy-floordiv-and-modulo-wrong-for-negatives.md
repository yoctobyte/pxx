---
track: N
prio: 75
type: bug
---

# NilPy: `//` and `%` are WRONG for negative operands, silently

Found 2026-07-20 in the operator sweep.

```python
print(-7 // 2)     # CPython -4    pxx -3
print(-7 % 2)      # CPython  1    pxx -1
print(7 % -2)      # CPython -1    pxx  1
print(7 // 2)      # 3             correct
print(7 % 2)       # 1             correct
```

Positive operands are right, which is why nothing caught it.

## Cause

Python's `//` floors — it rounds toward NEGATIVE INFINITY — and its `%` takes
the sign of the DIVISOR, with the identity `a == (a // b) * b + (a % b)`
holding for every sign combination. Pascal's `div` truncates toward zero and
its `mod` takes the sign of the DIVIDEND. NilPy lowers straight onto the
Pascal pair.

## Shape

Both need a correction on the lowered result, or a pair of pylib helpers:

```
floordiv(a, b) = (a div b) - ord((a mod b <> 0) and ((a < 0) <> (b < 0)))
pymod(a, b)    = ((a mod b) + b) mod b        -- for b <> 0
```

Keep them together: the identity above must hold, and fixing one without the
other breaks it.

Division by zero already raises; that behaviour should not change.

## Why p75

Silent, and it is arithmetic — the class of bug that produces a plausible
number and corrupts everything downstream. uforth is a Forth VM whose whole
job is integer arithmetic; it has 6 `%` sites and 1 `//`, and Forth's own
`/MOD` semantics are floored, so the conformance suite tests exactly this.

## Related, found at the same time

`10 / 3` prints `3.333333333333334` where CPython prints
`3.3333333333333335` — a float REPR difference (Python emits the shortest
string that round-trips, 17 significant digits here; pxx emits 16). Cosmetic
next to the above, but it will show up in any output diff, so it needs its
own decision about whether NilPy matches CPython's repr exactly.

## Gate

`test-nilpy` green with every sign combination of `//` and `%` diffed against
CPython, plus the round-trip identity + `--tier quick` + self-host
byte-identical + `make fpc-check`.
