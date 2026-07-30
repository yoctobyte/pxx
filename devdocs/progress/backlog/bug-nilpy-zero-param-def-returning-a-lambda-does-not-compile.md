---
track: N
prio: 45
type: bug
---

# A zero-parameter def returning a lambda does not compile

```python
def mkl():
    return lambda x: x + 1

f = mkl()
print(f(1))
```

```
error: unexpected token
```

The identical code with a parameter compiles and runs:

```python
def mkl(n):
    return lambda x: x + n     # fine — 101 for mkl(100)(1)
```

So it is the zero-parameter ENCLOSING form, not the lambda. A zero-parameter def
returning a NESTED DEF is fine too (`def mk0(): def inner(x): ...; return inner`
— covered by test_nilpy_return_nested_def.npy), which narrows it to the lambda
lowering's handling of an enclosing routine with no parameters.

Reported in [[bug-nilpy-returning-a-nested-def-yields-none]] as a neighbouring
gap found while narrowing it; that ticket's own subject is fixed and this one is
not.

## Gate

`make test-nilpy` plus a `.npy` with a zero-parameter and a one-parameter def
each returning a lambda, both called, diffed against CPython.
