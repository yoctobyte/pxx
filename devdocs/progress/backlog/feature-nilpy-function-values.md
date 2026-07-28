---
track: N
prio: 45
type: feature
---

# NilPy: a function is a VALUE — bind it to a name, store it, call it back

Three spellings, all ordinary Python, all rejected today (measured against
`compiler/pascal26` at 8ae0f99f):

```python
def add(a, b):
    return a + b

f = add            # pascal26: error: unexpected token   near:  add >>> f
g = lambda x: x+1  # pascal26: error: unexpected token   (statement-level lambda)
hs = [add]
print(hs[0](3, 4)) # calling a function VALUE out of a container
```

`PyMakeFuncValue` already BUILDS a function value (a def handed to a
`Callable[...]` parameter marshals correctly since
[[bug-nilpy-callable-return-abi-mismatch]]), and `pyboundfn_new` /
`pyboundfn_bind_var` lift a captures-only nested def into a real proc. What is
missing is the other two halves:

1. **the bare def NAME as an expression** in an assignment / a literal — today
   the parser only accepts a def name in CALL position, so `f = add` does not
   parse at all;
2. **the CALL side on a value** — `f()`, `hs[0](5)`, `d["k"](x)` — invoking
   whatever the name/element holds rather than a statically resolved proc.

`lambda` as a statement-level assignment (`g = lambda ...`) is the same gap seen
from the lambda side: a lambda in ARGUMENT position works
(`sorted(xs, key=lambda p: p[1])`, `bind(..., lambda e: ...)`), because that path
builds the value where the parser expects an expression.

## Why it matters here

songformatter's `convertrawtext.py` and the render backends pass functions
around (an injected canvas backend is a set of callables), and every Python
program that builds a dispatch table writes `handlers = {"x": on_x}`. It is also
the shape [[feature-nilpy-lambda-compiled-closure]] needs: once a lambda lifts to
a real proc, the value it produces has to be storable and callable.

## Gate

`make test-nilpy` with a case covering all three spellings, CPython-diffed, plus
a call through a dict/list element.
