---
track: N
prio: 40
type: bug
blocked-by: []
---

# Float printing loses the last 1-2 significant digits vs CPython's shortest round-trip repr

Found by proactive CPython-diff sweeping.

```python
print(10 / 3)
print(1 / 3)
```
CPython (Python's `repr`/`str` for float is the SHORTEST decimal string that
round-trips back to the exact same IEEE 754 double):
```
3.3333333333333335
0.3333333333333333
```
pxx:
```
3.333333333333334
0.333333333333333
```

Both are wrong in the same direction: pxx's float-to-string conversion is
truncating/rounding to fewer significant digits than CPython's algorithm
keeps, so the printed value does not round-trip back to the identical double
(a real, if usually cosmetic, divergence — it would matter for anything that
re-parses printed floats, e.g. a round-trip test, a serialized config, or
`float(str(x)) == x` style logic, all of which CPython guarantees and pxx
currently does not).

## Scope note

This is a numerics/formatting question (the float→string conversion routine,
presumably in the RTL or pylib's float-to-str path), not specific to any one
`.npy` construct — every `print`/`str()`/f-string of a float likely goes
through the same routine, so the fix (whatever it is — more significant
digits kept, or a proper shortest-round-trip algorithm like Grisu/Ryu) is a
single shared fix with broad payoff. Not investigated further or attempted
this pass: pinning down exactly which routine renders a float to text needs
its own dedicated look (RTL float-to-string vs a NilPy-specific formatter),
and fixing a numeric-formatting algorithm deserves care and its own precise
verification against many values, not a rushed patch mid-sweep.

## Gate

A `.npy` case with several float values whose shortest round-trip repr needs
16-17 significant digits (as CPython's does), diffed directly against
CPython's own `print()` output, gated in `test-nilpy` + self-host
byte-identical.
