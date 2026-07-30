---
track: N
prio: 55
type: bug
---

# Two function-value shapes that do not COMPILE

Found while narrowing
[[bug-nilpy-returning-a-nested-def-yields-none]]; both are parse-level, both
are ordinary Python.

## 1. A zero-parameter enclosing def returning a lambda

```python
def mkl():
    return lambda x: x + 1

f = mkl()
print(f(1))          # pascal26: error: unexpected token
```

The same with a parameter on the enclosing def compiles and runs correctly:

```python
def mk(n):
    return lambda x: x + n     # fine
```

So it is the empty parameter list of the ENCLOSING def, not the lambda.

## 2. Calling a function-valued LOCAL inside a def

```python
def go() -> None:
    g = mkl()
    print(g(1))      # pascal26: error: unexpected token near: g
```

The identical two lines at module level compile and run. So the call-through-a-
local path exists but is not reached inside a def body.

Both are compile errors rather than wrong answers, but they block the natural
way to USE a function value, which is what makes them worth more than their
prio suggests: the feature is largely unusable inside functions without them.

## Gate

`make test-nilpy` + self-host byte-identical, plus a matrix of {top-level def,
nested def, lambda} x {returned, stored in a local, stored in a global} x
{called at module level, called inside a def}.
