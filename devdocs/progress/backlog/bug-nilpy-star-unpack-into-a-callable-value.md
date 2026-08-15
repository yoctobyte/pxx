---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`fn(*args)` where `fn` is a callable VALUE (a parameter, a dict entry) reports \"expected expression\": every star arm keys on the CALLEE'S signature, and a value has none at the call site. This is the last piece of the plain decorator idiom."
---

# `*unpacking` into a callable VALUE

```python
def deco(fn):
    def wrapper(*args):
        return fn(*args)          # pascal26: error: expected expression
    return wrapper

def add(a, b):
    return a + b

f = deco(add)
print(f(2, 3))                    # CPython 5
```

Measured 2026-08-15. The other three pieces of this idiom now work — a
variadic def taken as a value
([[bug-nilpy-a-star-args-def-taken-as-a-value-is-called-with-loose-arguments]]),
a collecting lambda
([[bug-nilpy-a-collecting-lambda-is-lifted-as-a-fixed-arity-one]]) and
`f(*xs)` into a collecting def
([[bug-nilpy-star-unpack-into-a-star-args-callee]]) — so this is what still
stands between NilPy and the commonest decorator in Python.

## Why every existing arm misses it

All four star arms dispatch on the callee's `ProcPyStarIdx` / `ParamCount`:
expand into its slots, splice into its packing, forward by arity, or take the
iterable form. `fn` is a variant holding a bound pair or a bound-fn object;
there is no `procIdx` to ask, so the argument loop reaches the `*` and reports
a syntax error pointing at the operand.

## The shape a fix probably takes

The arity is a run-time fact, and the dynamic bridge is already arity-indexed
(`pybound_callv0..4`, `pyvar_callv*`). So this wants the same dispatch
`PyStarForwardCall` builds for a named callee — `case len(args) of 0: callv0;
1: callv1(args[0]); ...` — over the VALUE path instead. That is a lowering
question, not a new runtime: the bridge already packs for a collecting callee
and already refuses past its ceiling.

`f(1, *xs)` and `f(*xs, **kw)` through a value are the same construct and
should land with it.

## Gate

`.npy` diffed against CPython: the decorator above; `fn(*args)` for operand
lengths 0..4; a written argument before and after the star; the callee being a
dict entry and a parameter; a collecting callee reached this way; and past the
bridge's ceiling raising rather than answering wrongly.
