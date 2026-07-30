---
track: N
prio: 40
type: bug
---

# A function with no `return` yields 0, not None — and `math.floor` yields a float, not an int

Two small type divergences from the same family (a Python value arriving with
the wrong static type), batched because each is a one-line expectation change
rather than a design question.

```python
def f():
    pass
print(f())            # CPython: None    pxx: 0

import math
print(math.floor(2.7), math.ceil(2.1))
                      # CPython: 2 3     pxx: 2.0 3.0
```

## 1. Implicit return is 0

A def with no value-returning `return` is typed `tyInteger` — that is
deliberate and documented in `pyparser.inc` ("A def with no value-returning
`return` is tyInteger, which is the harmless case"). It is harmless for control
flow, but the value is observable: `print(f())` shows `0`, `f() is None` is
false, and a caller storing the result gets an int where Python guarantees
None.

This is the same axis as the deliberate `None -> 0` coercion in `pyvar_to_int`
(kept for the `Optional[int]` contract uforth relies on), so the fix has to be
careful not to disturb that — see the note on
[[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]. The narrow
change is to type a value-less def's result as the None sentinel rather than
integer 0, so only the RENDERED value and identity comparisons change.

## 2. `math.floor` / `math.ceil` return a float

Python's `math.floor` and `math.ceil` return an **int** (since 3.0); pxx returns
the double. Visible immediately through `str()` (`2.0` vs `2`), and it
propagates: an index computed with `math.floor` is a float, and a float
reaching an index or a `%d` format is a different bug one layer on.

`round()` has the same question — `round(2.7)` should be an int, and
`round(2.7, 2)` a float — but `type()` is not implemented so it could not be
checked directly here; verify both when fixing.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` printing the four
expressions above with CPython's own output, and `f() is None` for the
value-less def.
