---
track: N
prio: 65
type: bug
---

# `str(None)` prints `0`, but `str(x)` with `x = None` prints `None`

```python
x = None
print(str(None))        # CPython: None    pxx: 0
print(str(x))           # CPython: None    pxx: None      <- correct
print("v=" + str(None)) # CPython: v=None  pxx: v=0
print(None)             # CPython: None    pxx: None      <- correct
```

A LITERAL `None` handed to `str()` is typed as integer 0 and formatted as such.
Bound to a name first it is a variant carrying the None sentinel and formats
correctly, and bare `print(None)` is correct too — so only the
literal-straight-into-`str()` route is wrong.

Silent: a `"prefix" + str(None)` in a message produces `prefix0`, which reads
like data rather than like a bug.

This is the literal end of the None-representation family
([[project_nilpy_none_routes_sentinels.md]]): the sentinel is right everywhere
it flows through a variant, and wrong where a literal is typed directly.

Found by sweeping builtins over argument types against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus a regression covering
`str(None)`, `str(x)`, `"" + str(None)` and f-string/`%` interpolation of a
literal None.
