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

## Gate

A `.npy` diffed against CPython: a list swap, a dict swap, a mixed
name/subscript target list, a three-element target list, a nested subscript
(`m[i][j], m[j][i] = ...`), an attribute-and-subscript mix, and an assertion
that the right-hand side is fully evaluated first (`h[0], h[1] = h[1], h[0]`
over distinguishable values).
