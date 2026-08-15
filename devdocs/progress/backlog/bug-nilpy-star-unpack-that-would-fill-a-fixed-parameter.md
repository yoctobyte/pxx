---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`g(*xs)` where `g` declares fixed parameters BEFORE its `*args` is refused: the split between those parameters and the packed tuple depends on len(xs), a run-time fact the compile-time packing cannot answer. Loud and self-naming, but CPython accepts it."
---

# `*unpacking` that would fill a fixed parameter

```python
def g(x, *rest):
    return x, rest

print(g(*[9, 8, 7]))     # CPython (9, (8, 7))
                         # pxx: "Nil Python: *unpacking that would fill a fixed
                         #       parameter of a collecting callee is not
                         #       supported yet (the split depends on the
                         #       operand's length)"
```

Split out of [[bug-nilpy-star-unpack-into-a-star-args-callee]] when the splice
landed (2026-08-15). The written-argument form `g(1, *xs)` works — only an
operand that has to REACH BACK over a fixed slot is refused.

## Why it is not the same fix

The splice that solved the sibling is a compile-time `extend`: every element
goes into the packed tuple. Here the first `len(xs) >= 1` elements belong to
`x` instead, and which they are is unknowable until the call runs.
`g(*[], 3)` binds x = 3; `g(*[9], 3)` binds x = 9 and rest = (3,) — the same
source, a different shape per operand.

## The shape a fix probably takes

Run-time distribution, and the pieces exist: `x := xs[0]` is a list getitem and
`rest := xs[1:]` a slice, both already lowerable. Bounded to the case where the
splice is the LAST positional (otherwise a written argument after it also
lands at a position nobody can compute); beyond that, an arity dispatch like
`PyStarForwardCall`'s.

A short operand must raise CPython's TypeError ("missing 1 required positional
argument"), not read past the end.

## Gate

`.npy` diffed against CPython: `g(*xs)` for operands shorter than, equal to and
longer than the fixed parameters; two fixed parameters; a fixed parameter with
a DEFAULT before the star; and the too-short case raising TypeError.
