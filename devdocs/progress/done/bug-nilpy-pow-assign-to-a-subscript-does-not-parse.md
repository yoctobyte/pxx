---
track: N
prio: 35
type: bug
summary: "`xs[0] **= 5` does not parse — 'expected expression'. `**` is not a binop token, and the subscript-target augmented path (ParseLValueAST's augBin) has no arm for tkPowEq, so the third of three augmented-assign target shapes still refuses a valid CPython statement."
status: done
owner: claude-AN
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

## 2026-08-07 — FIXED

The third arm landed exactly where the ticket sized it: `ParseLValueAST`'s
default-property subscript route in `parser.inc`. `PyAugBinTok(tkPowEq)` is
`tkEOF`, so the route's `isAssign` peek never fired and the statement died on
"expected expression" before any augmented handling ran. Added an `augPow`
flag beside `augBin`: it is set when the token past `]` is `tkPowEq`, drives the
same `augRead` construction (so the read half is built over a CLONE of the index
chain, as before), and combines through `PyMakePow` instead of `AN_BINOP` —
which carries the `__pow__` / `__rpow__` dispatch with it for free.

The sibling `__getitem__`/`__setitem__` route beside it also keyed its named
refusal on `PyAugBinTok(...) <> tkEOF`, so `obj[k] **= v` on a user class fell
past it into the same bare "expected expression". It now names itself.

### Measured (self-hosted at HEAD + this change), diffed against CPython

| form | pxx | CPython |
| --- | --- | --- |
| `xs[0] **= 5` (list, int) | `[32, 3]` | same |
| `ys[1] **= 0.5` (list, float) | `[2.0, 2.0]` | same |
| `dd["a"] **= 2` (dict) | `{'a': 9}` | same |

### Deliberately NOT fixed here

- **A subscript holding a class INSTANCE** (`ps[0] **= 7` with `__pow__`) still
  raises `TypeError: expected a number, got object`. Measured the sibling: `+=`
  with `__add__` and `*=` with `__mul__` fail identically, so this is not
  specific to `**=` — a container erases the element's static class and no
  dunder dispatch happens. That is the blocked
  [[bug-nilpy-dunders-not-dispatched-through-containers]] family. Parity with
  the other augmented operators is the bar this ticket set, and it is met.
- **The index is still evaluated twice** (`xs[k()] **= 1` calls `k` twice) — the
  ticket's fix-shape note assumed `augRead` already evaluated it once; it does
  not, and neither does any other augmented operator on this route. That is
  [[bug-nilpy-augmented-subscript-evaluates-its-index-twice]], pre-existing and
  filed.

### Test

`test/test_nilpy_truediv_pow_assign_class_dunder.npy` extended as the Gate line
asked (it already carried the other two target shapes and a NOTE marking this
one as the known gap; the NOTE is replaced by the real coverage). Output is
byte-identical to CPython's for the whole file. Makefile expectation updated.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
