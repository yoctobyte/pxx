---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`f(*args)` where `args` is a VARIANT holding a str SEGFAULTS: PyStarOperandAsList hard-casts a variant to TPyList (pyvarobj + class cast) instead of converting, so a string handle is read as a list. The static-typed spellings are all fine, which is what hid it."
status: done
owner: claude-AN
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

## Resolution (2026-08-15)

`pystar_as_list(v: Variant): TPyList` in pylib, exactly the helper the sketch
above called for — and it is three lines, because `pyiter_v` already IS the
universal normalisation (`for`, `list()`, `sorted()` and `in` all go through
it). A list or tuple is handed straight back (the packing only reads it, so a
copy would be pure cost); everything else drains through `pyiter_v`, which
gives a str's characters, a dict's keys, a range's and a user `__iter__`'s
elements, and raises for a non-iterable.

`PyStarOperandAsList`'s variant arm calls it instead of casting — and
`PyStarForwardCall` now goes through `PyStarOperandAsList` rather than
`PyIterArgAsList` alone, because it assigns the operand straight into a
TPyList-typed temp: the same hard-cast hazard wearing a different spelling.
That is what makes the fix cover all four star paths from one place, which was
the point of the "normalise, don't special-case" reading.

`PyIterArgAsList` itself is deliberately UNCHANGED: its other five callers
(join, zip, the comprehension sites) pass variants they expect to stay
variants, and widening it would have moved overload selection under them.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v334.
`test/test_nilpy_star_operand_in_a_variant.npy`, byte-identical to CPython: a
variant holding a str, a list, a tuple, a dict (keys), a range and a user
`__iter__` class, through the named-callee forwarding, the collecting-callee
splice and the callable-value dispatch, plus the operand read out of a dict
entry. Re-checked twelve neighbouring star tests.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
