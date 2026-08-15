---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`f(*xs)` where `f` itself declares `*args` reports \"expected expression\" — the forwarding arm explicitly excludes a callee that collects, and the compile-time expansion has no fixed slots to expand into. Wrapper-to-variadic forwarding is refused in both directions of the star."
---

# `*xs` into a callee that declares `*args`

```python
def f(*a):
    return a

xs = [1, 2]
print(f(*xs))            # CPython (1, 2)
                         # pascal26:3: error: expected expression   near: print f >>> xs
```

Measured 2026-08-15, splitting out of
[[bug-nilpy-star-unpack-into-a-builtin-or-a-bound-method-is-refused]]. Loud, and
the message names neither the star nor the callee.

Both existing star paths decline it by construction: the run-time forwarding arm
is guarded on `ProcPyStarIdx[procIdx] < 0` (a callee that COLLECTS is not what
it dispatches into), and the compile-time expansion fills declared slots, of
which a `*args` callee has none to fill.

## The shape a fix probably takes

It should be the CHEAPEST of the star cases rather than the hardest: the callee
packs its positionals into a `TPyList` anyway (`PyPackStarArgs`), so a starred
operand wants to be SPLICED into that packing — `extend` where a written
argument `append`s — instead of expanded into slots. That also gives `f(1, *xs)`
and `f(*xs, 3)` for a variadic callee, since the packing already walks the whole
chain in order.

The marker has to survive from the argument parse to `PyPackStarArgs`, and the
`ASTIVal` encoding on an AN_ARG node is already spoken for (0 positional, >0
keyword slot, <0 kwargs pair) — pick the representation deliberately; a
side-table keyed by node index is one option.

Not to be confused with `*args` FORWARDED out of a wrapper into an ordinary
callee (`def w(*a): return f(*a)`), which works and is owned by
`test/test_nilpy_star_forward.npy`. This is the other direction.

## Gate

`.npy` diffed against CPython: `f(*xs)` into `def f(*a)`; with fixed parameters
before the star parameter; `f(1, *xs)` and `f(*xs, 3)`; an empty operand; a str
operand; `*args` re-forwarded from one variadic to another; and `f(*xs, **kw)`.
