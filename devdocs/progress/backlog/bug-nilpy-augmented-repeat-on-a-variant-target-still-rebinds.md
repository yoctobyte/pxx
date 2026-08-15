---
track: N
prio: 20
type: bug
blocked-by: []
summary: "A dict VALUE as the `*=` target still rebinds, so an alias of it keeps the old contents. The parameter half landed 2026-08-15 (pymul_v_inplace); this is the residue, and `+=` has the same split."
---

# `*=` on a variant-typed target still rebinds

```python
def double(xs):
    xs *= 2

g = [4, 5]
double(g)
print(g)                 # CPython [4, 5, 4, 5]     pxx [4, 5]

dd = {"k": [3]}
dz = dd["k"]
dd["k"] *= 3
print(dd["k"], dz)       # CPython [3,3,3] [3,3,3]  pxx [3,3,3] [3]
```

Split out of [[bug-nilpy-augmented-sequence-repeat-rebinds-instead-of-mutating]]
when the statically-typed half landed (2026-08-15). A bare name and a FIELD
whose type is known both mutate correctly now; what is left is every target
that reads as a VARIANT.

`PyAugMulNode`'s in-place arm is gated on `PyNodeIsPyList(left)`, which needs a
`tyClass`/TPyList node. A parameter, a dict value and a list element are all
variants, so they fall to `pylist_repeat` — the fresh-list path — and the store
puts a NEW object where the alias expects the old one mutated.

`+=` has exactly the same split and the same known gap: `parser.inc`'s comment
at the `extend` arm says so ("PyNodeListCi above only recognises a STATICALLY
tyClass/TPyList target, so this is the variant case the in-place extend cannot
reach"). One rule, two operators, one missing half each — fix them together.

## Shape of a fix

A run-time twin: `pyvar_repeat_inplace(const v: Variant; n: Int64): Variant`
that mutates when `v` holds a mutable TPyList and otherwise computes the
ordinary product, plus the `+=` equivalent. The risk to weigh first is that
routing EVERY variant `*=` through it must reproduce the arithmetic path
exactly — a variant holding an int must still multiply — so the fallback has to
be the same routine the binop lowering uses, not a re-implementation.

Worth checking while there: whether the in-place form should skip the store on
the variant path too, the way the typed one now does
(`PyAugMulInPlace`) — storing the same handle back through a field target
released the list before the append ran, which is the trap that half of the fix
exists to avoid.

## Gate

`.npy` diffed against CPython: `xs *= 2` on an unannotated parameter with the
caller observing; a dict value with an alias; a list element; a variant holding
an int/float/str (arithmetic and str-repeat unchanged); and every row of
`test_nilpy_augmented_repeat_mutates_in_place.npy` still green.

## Resolution (2026-08-15) — the PARAMETER half

`pymul_v_inplace(a, b)`: a mutable list is repeated in place and the same
handle answered; everything else is `pymul_v` itself, **called** rather than
re-implemented, which is what makes the arithmetic, str-repeat and tuple rows
provably unchanged. The tuple/frozenset question is not asked here at all —
`pylist_repeat_inplace` owns it, and that is the one place that knows the
run-time kind.

The store around it STAYS, unlike the statically-typed arm: when the fallback
runs, the product is a new value the target must receive. Only the typed arm
can skip the store, and only because it can prove nothing new was built.

One measurement worth keeping: **a boxed integer wears VT_INT (1) or VT_INT64
(2) depending on where it came from**, so the first version — which tested tag
2 alone — compiled, ran, changed nothing, and looked exactly like the arm not
existing. Bool (4) is accepted too, since `xs *= True` is a legal repeat count.

## What is left

A dict VALUE as the target (`dd["k"] *= 3`) still rebinds: the value is right,
an alias of it keeps the old contents. Container reads ARE aliases here —
measured, `dz = dd["k"]; dz.append(9)` is visible through `dd` — so the residue
is in how the subscript target's augmented store is built, not in the container
model. Left on this ticket, which returns to the backlog at prio 20.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v338.
`test/test_nilpy_augmented_repeat_mutates_in_place.npy` extended and still
byte-identical to CPython: the parameter case with the caller observing, and
the same parameter over int, str, float and tuple (which must not mutate).
