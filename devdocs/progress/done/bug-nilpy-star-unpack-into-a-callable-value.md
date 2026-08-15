---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`fn(*args)` where `fn` is a callable VALUE (a parameter, a dict entry) reports \"expected expression\": every star arm keys on the CALLEE'S signature, and a value has none at the call site. This is the last piece of the plain decorator idiom."
status: done
owner: claude-AN
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

## Resolution (2026-08-15)

`PyStarDynCall`, the same shape `PyStarForwardCall` builds for a named callee:
every positional argument — written and starred alike — goes into ONE list at
the call site, `pystar_check_arity(list, 0, 4)` is hoisted as the guard, each of
the four slots is read once into a hidden variant local (`pystar_arg` yields
None past the end, and a ternary arm cannot carry hoisted setup), and the arms
`pyvar_callv0..4` fold into a ternary chain on the list's length.

Putting written and starred arguments in the SAME list is what makes
`fn(1, *xs, 4)` fall out for free; the first star switches the loop over and
the already-parsed arguments move into the list in order. The callee itself is
also read once into a hidden local — it appears in all five arms, and unlike
the plain dynamic call its base may be an arbitrary expression.

Four is the ceiling because that is where the dynamic bridge stops. Past it the
guard raises rather than picking an arm that would call the body with the wrong
shape.

### Two more defects fell out of the decorator being end-to-end

The idiom needs `def wrapper(*args)` to CAPTURE `fn`, which routes it through
`PyNestedDefClosureValue` rather than the pair — a third callable
representation, and both halves of it were wrong:

1. it never emitted `pyboundfn_setstar`, so the body got loose arguments where
   its signature declares a TPyList (the same fix the lambda lifter got in
   [[bug-nilpy-a-collecting-lambda-is-lifted-as-a-fixed-arity-one]] — a sibling
   left wrong, which is the recurring shape here);
2. its header scan counted only an ident preceded by `(` or `,`, so `*args` was
   not counted at all and `pyboundfn_setown` published ZERO own parameters. The
   bridge then placed the captures one slot too far left: `len(args)` came back
   1275068416 and the capture itself read empty. That one is the more
   interesting of the two — the star was invisible to a scan that never had to
   think about it.

### Still open

A star operand that is a VARIANT holding a str segfaults —
`PyStarOperandAsList` hard-casts a variant to TPyList instead of converting.
Pre-existing and shared with the older forwarding path (`two(*args)` where
`args` is a str parameter crashes identically), so it is filed separately as
[[bug-nilpy-a-star-operand-in-a-variant-is-cast-not-converted]]. A str LITERAL
operand is fine and is covered here.

### Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN (no builtin change, so
no pin). `test/test_nilpy_star_unpack_into_a_callable_value.npy`,
byte-identical to CPython: arity 0..4 through a value, written arguments mixed
with a star, a str literal operand, the callee out of a dict, a COLLECTING
callee reached this way, a lambda as the value, and the decorator itself over
two different arities. Re-checked ten neighbouring star/callable tests.

## Log
- 2026-08-15 — resolved, commit c35f61df0.
