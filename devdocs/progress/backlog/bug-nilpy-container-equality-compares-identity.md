---
track: N
prio: 55
type: bug
---

# NilPy: `==` on a list or dict compares IDENTITY, not contents

Found 2026-07-20 in the operator sweep. Silent.

```python
xs = [1, 2]
ys = [1, 2]
print(xs == ys)     # CPython True    pxx False
print(xs == xs)     # True            correct, and why nothing caught it

a = {"k": 1}
b = {"k": 1}
print(a == b)       # CPython True    pxx False
```

A list and a dict are class values, so `==` compares the POINTERS. Python
compares element-wise (and for dicts, key/value-wise, order-insensitively).

Comparing a container with ITSELF is True either way, which is exactly the
case a hand-written test reaches for — so this survived the whole list and
dict test suite.

## Shape

`pylist_eq(a, b)` and `pydict_eq(a, b)` in pylib, dispatched from `==` / `!=`
on a TPyList- or TPyDict-typed operand, the way `in` now dispatches on the
container's class (c49064af). Element comparison is `PyVarEq`, which already
exists and already compares strings by CONTENT.

Note for the dict case: Python's dict equality is order-INSENSITIVE, while
TPyDict preserves insertion order — so it must compare by lookup, not by
walking both arrays in step.

`is` must keep comparing identity; that distinction is the whole reason
Python has both.

## Gate

`test-nilpy` green with equal-contents-different-objects cases for both
containers, plus an `is` case to pin that identity still means identity +
`--tier quick` + self-host byte-identical + `make fpc-check`.
