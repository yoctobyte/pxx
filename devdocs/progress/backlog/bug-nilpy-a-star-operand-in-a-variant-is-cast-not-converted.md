---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`f(*args)` where `args` is a VARIANT holding a str SEGFAULTS: PyStarOperandAsList hard-casts a variant to TPyList (pyvarobj + class cast) instead of converting, so a string handle is read as a list. The static-typed spellings are all fine, which is what hid it."
---

# A star operand inside a variant is cast, not converted

```python
def two(a, b):
    return a + b

def fwd(args):
    return two(*args)

print(fwd("xy"))       # CPython 'xy'      pxx: Segmentation fault
print(fwd([1, 2]))     # CPython 3         (never reached)
```

Measured 2026-08-15 while landing
[[bug-nilpy-star-unpack-into-a-callable-value]]; PRE-EXISTING and shared, not
introduced there — the older forwarding path above crashes identically, and so
does the new callable-value path.

## Root cause

`PyStarOperandAsList` normalises a star operand, and its variant arm is:

```
pyvarobj(node)  ->  AN_CLASS_CAST to TPyList
```

An unconditional hard cast. `PyIterArgAsList` (called first) explodes a str and
drains a user iterator, but it keys on the node's STATIC type — a variant is
none of those, so it passes through untouched and the cast reinterprets
whatever the variant holds as a list object.

The static spellings are all correct: `f(*"ab")`, `f(*xs)` with `xs: list`,
`f(*(1, 2))`. Only a variant — which is what an unannotated parameter, a dict
entry and a container element all are — reaches the bad arm. That is why every
star test passes while the commonest real shape crashes.

## The shape a fix probably takes

A RUN-TIME normalisation to sit where the compile-time one cannot decide:
`pystar_as_list(v: Variant): TPyList` — pass a list/tuple through, explode a
str into characters, drain an iterator or a user `__iter__`, and raise
CPython's "argument after * must be an iterable" for anything else. Then
`PyStarOperandAsList`'s variant arm calls it instead of casting.

One helper, one call site, and every star path inherits it — the same
"normalise, don't special-case" move `PyIterArgAsList` already made for the
static types.

## Gate

`.npy` diffed against CPython: a variant parameter holding a str, a list, a
tuple, a dict (spreads KEYS), a set, a range, a generator and a user iterable;
a non-iterable raising TypeError with CPython's wording; through the named
callee path, the collecting-callee splice and the callable-value dispatch.
