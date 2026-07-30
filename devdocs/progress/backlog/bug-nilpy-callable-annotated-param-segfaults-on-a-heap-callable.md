---
track: N
prio: 55
type: bug
---

# A `Callable[...]`-annotated parameter segfaults when the argument is a heap callable

```python
from typing import Callable

def apply(f: Callable[[int], int], v: int) -> int:
    return f(v)

def top(x: int) -> int:
    return x + 1

g = lambda x: x + 2
print(apply(top, 5))    # 6  — a plain compiled def is fine
print(apply(g, 5))      # SEGFAULT (CPython: 7)
```

The same function without the annotation works for both:

```python
def apply2(f, v):
    return f(v)         # 6 and 7, matching CPython
```

So the annotation is what breaks it: `Callable[...]` evidently types the
parameter as a raw code address, and every callable that is a heap OBJECT — a
lifted lambda (`pyboundfn`), a pyeval closure, a returned nested def — is then
called as if its pointer were code.

Pre-existing: reproduced on the compiler built before
[[bug-nilpy-returning-a-nested-def-yields-none]] landed, so that fix neither
caused nor cured it. Found while gating that ticket (its gate asks for exactly
this shape).

## Shape of a fix

Type a `Callable[...]` parameter as tyVariant, the same as an unannotated one,
so the call site takes the dynamic-call path (`pyvar_callv*`) that already
probes for closure / bound-fn / bound-method payloads. The annotation should
inform diagnostics and arity, not the ABI.

## Gate

`make test-nilpy` plus a `.npy` passing a plain def, a lambda, a returned nested
def and a bound method through a `Callable[...]` parameter, diffed against
CPython.
