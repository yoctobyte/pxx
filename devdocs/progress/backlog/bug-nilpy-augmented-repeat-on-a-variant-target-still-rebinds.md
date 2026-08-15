---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`xs *= 2` mutates in place only when the target's STATIC type is a TPyList. A dict VALUE or an unannotated parameter reads as a variant, so those still rebind and an alias keeps the old contents — the surviving half of the `*=` in-place work."
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
