---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`f(*xs)` where `f` itself declares `*args` reports \"expected expression\" — the forwarding arm explicitly excludes a callee that collects, and the compile-time expansion has no fixed slots to expand into. Wrapper-to-variadic forwarding is refused in both directions of the star."
status: done
owner: claude-AN
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

## Resolution (2026-08-15)

Spliced, as the sketch above guessed — `extend` where a written argument
`append`s, inside `PyPackStarArgs`, so source order (`f(1, *xs, 9)`) comes out
right for free and the tuple marking, the defaults filler and the keyword bind
are all reused unchanged.

The marker is `PY_ARG_SPLICE`, a sentinel `ASTIVal` on the AN_ARG node rather
than a side table: the other meanings there are 0 = positional, >0 = a
parameter SLOT (bounded by MAX_PROC_PARAMS = 32) and <0 = a `**kwargs` pair, so
a value at 1000000 cannot collide, and `PyPackStarArgs` runs immediately after
the argument loop that sets it — the marker never outlives one call's parse.

THREE argument loops had to learn it, which is the usual shape here: the
plain-proc loop (`parser.inc`), `PyParseStarMethodArgs` (a typed receiver) and
`PyParseClassMethodCall` (the variant-receiver path). Each already had the
sibling arm for star-into-FIXED next to it, which is what made them findable.

The operand goes through `PyStarOperandAsList`, the one normalisation every
star operand passes, so `f(*"ab")` spreads characters and `f(*(7, 8))` a tuple.

### Refused, deliberately

`g(*xs)` where `g` declares fixed parameters BEFORE the star: the split between
those parameters and the tuple depends on `len(xs)`, a run-time fact, so a
compile-time packing cannot answer it. It now names itself rather than
reporting "expected expression". Filed as
[[bug-nilpy-star-unpack-that-would-fill-a-fixed-parameter]].

Also still open, and the last piece of the decorator idiom: `fn(*args)` where
`fn` is a callable VALUE rather than a def name — that call has no signature at
the call site at all. Filed as
[[bug-nilpy-star-unpack-into-a-callable-value]].

### Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN (no builtin change, so
no pin). `test/test_nilpy_star_unpack_into_a_collecting_callee.npy`,
byte-identical to CPython: bare, leading and trailing written arguments, two
splices in one call, an empty operand, a str and a tuple operand, a fixed
parameter filled by a written argument, wrapper-to-variadic re-forwarding, the
method form with and without a fixed parameter, and the result's type name.
Re-checked the eleven existing star `.npy` tests against their oracles.

## Log
- 2026-08-15 — resolved, commit b7bb489f5.
