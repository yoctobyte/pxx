---
slug: bug-n-a-function-value-has-no-name
track: N
type: bug
prio: 30
status: backlog
owner: ""
created: 2026-09-19
found-by: frankH
tags: [nilpy, introspection, callables, argparse]
blocked-by: []
summary: "A def as a VALUE carries no name. `f.__name__` on a def name refuses at COMPILE time (`undefined variable (f)`), and on a function held in a variable or parameter raises AttributeError at run time, because the boxed callable has only a code address. repr() shows it too: `<function at 0x5ae82b>`, where CPython prints `<function f at 0x...>`. A user class and, since 2026-09-19, a builtin type both answer __name__, so a def is the one callable that cannot."
---

# Measured 2026-09-19

```python
def size(t):
    return t
print(size.__name__)   # NilPy: compile error `undefined variable (size)`
f = size
print(f.__name__)      # NilPy: AttributeError
```

# Where it shows in a real program

argparse builds `invalid <type name> value: 'x'` from `type.__name__`.
tsp/view/__main__.py passes `type=_size`, a def. CPython prints
`argument --size: invalid _size value: 'wide'`. lib/rtl/mimic_argparse.py
falls back to repr, so NilPy prints `invalid <function at 0x5ae82b> value`.
That case (`view --size wide`) was left OUT of
test/test_nilpy_argparse_tsp_surface.cases for this reason; put it back when
this ticket lands.

# Two halves, one representation

- The static spelling `size.__name__`: the frontend knows the def, so it can
  fold to a string literal.
- The dynamic spelling needs the name in the boxed callable. It is the same
  representation that repr() reads, so fixing it fixes both.
