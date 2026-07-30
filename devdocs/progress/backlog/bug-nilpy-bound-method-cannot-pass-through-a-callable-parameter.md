---
track: N
prio: 40
type: bug
---

# A bound method cannot be passed through a `Callable[...]` parameter

```python
class C:
    def m(self, x: int) -> int:
        return x + 100

def apply(f: Callable[[int], int], v: int) -> int:
    return f(v)

apply(C().m, 5)
```

```
TypeError: parameter f is declared Callable[...], which carries a code address
only, and a BOUND METHOD also needs its receiver — pass a plain function, a
lambda, or declare the parameter without an annotation
```

CPython prints 105. The residual of
[[bug-nilpy-callable-annotated-param-segfaults-on-a-heap-callable]], which fixed
the plain def, the lambda/closure and the lifted bound-fn cases (all three
segfaulted); this one is a representation limit rather than a coercion bug, so
it was split off rather than bodged.

**The workaround works and is what the message says**: drop the annotation.
`def apply(f, v): return f(v)` takes a bound method, a lambda and a def alike —
an unannotated parameter is a VARIANT, and the dynamic-call path
(`pyvar_callv<n>`) already tells all four callable shapes apart, receiver
included.

## Why

`Callable[...]` registers a `$proctype` signature and types the parameter
tyPointer (`PyAnnTypeAt`, the `callable` branch). A bound method is a
{code, receiver} PAIR — 16 bytes — and a pointer parameter has room for the code
half only. Dropping the receiver would call the method with whatever happened to
be in the Self register, which is the silent-wrong-value class this project
refuses.

## Shape of a fix

Type a `Callable[...]` PARAMETER as tyVariant and let the call go through
`PyMakeDynCall` — the same dispatcher the unannotated form already uses, which
handles all four shapes. The annotation then informs arity and diagnostics
rather than the ABI, which is what it does for the RESULT already (the declared
result is documented as a hint, not an ABI — see the `callable` branch's own
comment).

The catch to check first: a Callable FIELD must stay tyPointer. uforth's
`native: Callable[[VM], None]` is read as a code address by the field-call path
(`PyWrapClosureFieldCall`), so the change has to distinguish the PARAMETER
context from the FIELD context inside `PyAnnTypeAt`, or move the decision to the
two callers.

## Gate

`make test-nilpy` plus the existing
`test/test_nilpy_callable_param_heap_callable.npy` extended with a bound method
and a bound method stored in a list, diffed against CPython — and uforth still
green, since it is the Callable-field user.
