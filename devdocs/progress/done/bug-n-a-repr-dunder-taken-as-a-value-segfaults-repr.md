---
slug: bug-n-a-repr-dunder-taken-as-a-value-segfaults-repr
title: taking obj.__repr__ as a value inside a def makes repr() of that class segfault
track: N
type: bug
prio: 70
status: done
---

## Repro (latest-ba3b84f1a2 and earlier)

```python
class N:
    def __init__(self, v):
        self.v = v
    def __repr__(self):
        return "X"
def bound():
    m = N(5).__repr__      # never called
    return m()
print(repr(N(2)))          # CPython: X    pxx: SIGSEGV
```

Found by a leak probe that called a helper taking `Node(5).__repr__`; every
`repr()` of `Node` in the program then crashed, before `bound` ran. At module
level the same line was fine.

## Cause

`.__repr__` after a dot counts as a value use (PyDValDotQualifies), so both
halves of the method's typing applied the function-object ABI: a variant
result. The signature (PyMethodUsedAsValue in PyRegisterClassMembers) did it
AFTER the str-dunder forcing, and the frame (PyParseDefHeader) likewise. The
repr arms and the runtime renderer call a str dunder expecting an AnsiString
result, so the variant frame was read as a string pointer.

## Fix

Both normalisations now leave a str dunder's AnsiString result alone. A bound
value of the method still works: PyMakeBoundMethod routes any non-variant
method through `$pyboundretwrap`, which boxes the string.

Test: `test/test_nilpy_a_repr_dunder_taken_as_a_value.py` (row reprval26).
