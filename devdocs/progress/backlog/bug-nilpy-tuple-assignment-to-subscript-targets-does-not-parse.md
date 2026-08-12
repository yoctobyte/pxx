---
track: N
prio: 52
type: bug
blocked-by: []
summary: "`h[i], h[j] = h[j], h[i]` — the in-place swap every sort and heap is built on — fails with 'expected expression'. A tuple assignment accepts NAME and ATTRIBUTE targets (`a, b = b, a` and `k.a, k.b = k.b, k.a` both work) but not a SUBSCRIPT, so the one idiom that needs it most is the one that does not parse"
---

# Tuple assignment to SUBSCRIPT targets does not parse

- **Type:** bug (compile error on ordinary code) — **Track N**
- **Found:** 2026-08-12, differential bug hunting — writing a binary heap,
  which cannot be written without it.

```python
h[p], h[i] = h[i], h[p]          # error: expected expression
d["x"], d["y"] = d["y"], d["x"]  # error: expected expression
```

## The boundary — targets, not values

| statement | result |
| --- | --- |
| `a, b = b, a` (names) | fine |
| `k.a, k.b = k.b, k.a` (attributes) | fine |
| `h[0], h[2] = h[2], h[0]` (list subscripts) | **error: expected expression** |
| `d["x"], d["y"] = d["y"], d["x"]` (dict subscripts) | **error** |
| `a, h[0] = h[0], 9` (mixed) | **error: undefined variable (a)** — the target list is not even scanned |

The right-hand side is fine in every row; it is the target list that stops at a
`[`. The mixed row's *different* message is the tell: the parser is not
recognising the statement as a tuple assignment at all, so `a` is read as an
expression statement.

## Why it matters

`x[i], x[j] = x[j], x[i]` is how Python swaps two elements — every sort, every
heap, every partition, every shuffle. Without it the code has to be rewritten
with a temporary, which is exactly the kind of edit
`devdocs/dev/parallel-tracks.md` calls a compiler-appeasement workaround.

## Where to look

The tuple-assignment target parse in `pyparser.inc`. Attributes already work,
so the target list is not name-only — it just stops one shape short. Expect the
usual receiver-shape split ([[project_nilpy_lvalue_vs_selector_path_must_both_know]]):
the lvalue path knows about `obj.field` targets but the subscript store lives
elsewhere. The assignment must also keep Python's evaluation order — the whole
right-hand side is evaluated BEFORE any target is stored, which is what makes
the swap work without a temporary, and a naive left-to-right lowering would
break `h[i], h[j] = h[j], h[i]` silently rather than loudly.

## 2026-08-12 — scoped, not started: why it is bigger than it looks

Read both halves before starting; the parse is the easy one.

**Target parse** (`PyParseUnpackAssign`, pyparser.inc ~17400): the target list
is hand-parsed as `ident [ '.' ident ]`, into parallel `names[]` / `flds[]`
arrays with a cap of 8. Adding `[expr]` there is straightforward — but it
changes what a target IS, from a pair of strings to a node, so `flds[]` wants
to become a node array and `PyUnpackTargetStore` a builder over it.

**The store** is where the work is. There is no reusable "store into this
subscript lvalue" builder: the `x[k] = v` lowering lives INLINE in
`parser.inc` (~4890-4970), inside the postfix loop, keyed on seeing `=` right
after the `]`, and it forks four ways — a static list (AN_INDEX), a dict
(TPyDict.setitem), a variant (PyMakeVariantSetItem), and a user class
(`__setitem__`, or PyClassErrCallNode when it declares none). A tuple target
list needs all four, from a context that has already consumed the `]` and has
a comma next.

So the honest shape is: **extract that fork into a `PyMakeSubscriptStore(base,
idx, val)` builder** in pyparser.inc, make the existing inline path call it,
and then the tuple-target case is a few lines on top. That refactor is the
ticket; doing it any other way grows a fifth copy of a fork that already has
four arms (devdocs/dev/normalise-dont-special-case.md).

Also required by Python's semantics, and easy to get wrong in the store: every
value is evaluated into a temp BEFORE any target is stored. The existing
unpack code already does this for names — the new stores must stay inside that
same phase, or `h[i], h[j] = h[j], h[i]` silently degrades to `h[i] = h[j];
h[j] = h[i]`, which is the exact bug the idiom exists to avoid and which no
error would report.

## Gate

A `.npy` diffed against CPython: a list swap, a dict swap, a mixed
name/subscript target list, a three-element target list, a nested subscript
(`m[i][j], m[j][i] = ...`), an attribute-and-subscript mix, and an assertion
that the right-hand side is fully evaluated first (`h[0], h[1] = h[1], h[0]`
over distinguishable values).
