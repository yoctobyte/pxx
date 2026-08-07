---
track: N
prio: 35
type: bug
summary: "`xs[0] **= 5` does not parse — 'expected expression'. `**` is not a binop token, and the subscript-target augmented path (ParseLValueAST's augBin) has no arm for tkPowEq, so the third of three augmented-assign target shapes still refuses a valid CPython statement."
---

# `**=` to a SUBSCRIPT target does not parse

- **Type:** bug (ordinary Python refused, at COMPILE time) — **Track N**
- **Found:** 2026-08-07, grepping the bug class while fixing
  [[bug-nilpy-truediv-and-pow-assign-on-a-class-instance-skip-the-dunder]].
- **Pre-existing** — identical on `stable_linux_amd64/default/pinned`.

## Measured

```python
xs = [2, 3]
xs[0] **= 5
print(xs)          # CPython [32, 3]
```

```
pascal26:2: error: expected expression
  near:   xs    >>>
```

`xs[1] /= 3` and `xs[0] += 1` on the same target are fine, so it is `**=`
specifically, and only on a subscript.

## Why it is a third arm

Augmented assignment has **three** target shapes in this frontend, each with its
own code:

| target | site | `**=` |
| --- | --- | --- |
| bare name (`e **= 2`) | `pyparser.inc`, the `tkPowEq` branch in the aug-assign statement | works |
| lhs expression (`h.d **= 2`) | `pyparser.inc`, the lhs-expression aug-assign site | fixed 2026-08-07 |
| subscript (`xs[0] **= 5`) | `parser.inc` `ParseLValueAST`, the `augBin`/`augRead` path | **still refuses** |

The common cause across all three is that **`**` is not a binary TOKEN** — it
lowers through `PyMakePow`, not `AN_BINOP` — so every arm keyed on
`PyAugBinTok` has nothing to return for it and must special-case `tkPowEq`
explicitly. Two of the three now do.

## Fix shape

Give `ParseLValueAST`'s augmented path a `tkPowEq` arm that desugars to
`target = target ** rhs` through `PyMakePow`, with the target subtree handled
the way `augRead` already handles it (the index expression must be evaluated
once — `d[f()] **= 2` calls `f` once, which is exactly why that path builds an
`augRead` rather than duplicating the subtree).

`PyAugDunderName` already answers `__ipow__`/`__pow__` for `tkPowEq`, so the
user-class case comes free once the arm exists — but note that a subscript
target holding a class instance goes through `PyAugClassDunderNode`, which is
in `pyparser.inc`; check whether `ParseLValueAST` can reach it before assuming.

## Gate
Per-fix loop. Extend `test/test_nilpy_truediv_pow_assign_class_dunder.npy` —
which already carries the other two target shapes and marks this one as the
known gap — with the subscript form over an int, a float and a class instance,
diffed against CPython.
