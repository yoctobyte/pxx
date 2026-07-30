---
track: N
prio: 45
type: bug
---

# Calling a function-valued LOCAL inside a def does not compile

Reported in [[bug-nilpy-returning-a-nested-def-yields-none]] while narrowing it:

```python
def mkl():
    return lambda x: x + 1

def go():
    g = mkl()
    g(1)          # error: unexpected token near g
```

The identical code at MODULE level compiles and runs. Note the reproducer above
also trips
[[bug-nilpy-zero-param-def-returning-a-lambda-does-not-compile]] — re-narrow
with a one-parameter maker (`def mkl(n): return lambda x: x + n`) to see whether
this is a second, independent gap or the same one. If it turns out to be the
same, resolve this as a duplicate rather than leaving both open.

## Gate

`make test-nilpy` plus a `.npy` calling a function-valued local inside a def and
at module level, diffed against CPython.
