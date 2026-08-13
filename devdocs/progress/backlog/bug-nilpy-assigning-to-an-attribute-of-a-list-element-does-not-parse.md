---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`xs[0].n = 9` is a compile error (\"expected expression\") on any list of objects — assigning THROUGH a subscript to an attribute does not parse at all. Reading it (`xs[0].n`) is fine, and so is binding the element first (`e = xs[0]; e.n = 9`), so only the store-through-subscript spelling is missing."
---

# Assigning to an attribute of a list element does not parse

- **Type:** bug (refused valid program) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-13, while measuring the lvalue side of
  [[bug-nilpy-attribute-off-a-subscript-of-a-call-result-yields-the-variant-tag]]
  (that ticket is about a wrong READ; this is the store, and it is a separate
  defect — filed rather than folded in so neither hides the other).
- CPython accepts and runs this.

## Repro

```python
class B:
    def __init__(self, n):
        self.n = n

xs = [B(3), B(4)]
xs[0].n = 9
print(xs[0].n, xs[1].n)   # CPython: 9 4
```

```
pascal26:6: error: expected expression
  near: xs     n >>>
```

## The boundary

| statement | pxx |
| --- | --- |
| `xs[0].n = 9` (list literal receiver) | **compile error** |
| `xs[0].n = 9` where `xs = mk()` (call result) | **compile error** |
| `mk()[0].n = 9` (no intermediate name) | **compile error** |
| `e = xs[0]; e.n = 9` | OK |
| `xs[0].n` as a READ | OK |
| `d["k"].n = 9` (dict receiver) | worth checking — not measured |

So the element and the attribute are each fine on their own; it is specifically
an assignment TARGET that continues `subscript → attribute` that has no parse.

## Why it is worth more than its rarity suggests

This is the ordinary Python spelling for mutating an object held in a list —
`items[i].count += 1` and friends — so any corpus program that keeps objects in
a list and updates them in place hits it. It fails LOUDLY, which is why it has
survived unnoticed: nothing silently computes a wrong number, the program simply
does not build, and the workaround (bind the element to a name first) is
invisible in the corpus once someone has applied it.

## Where to look

The assignment-target parser, not the expression parser — the read path already
handles this chain. `PyUnpackTargetStore` / the target-parsing entry that
[[project_nilpy_lvalue_vs_selector_path_must_both_know]] describes: member
access has TWO parsers split by receiver shape, and a store target that
continues past a subscript into a `.name` is the arm that is missing. The
tuple-assignment work already extended targets to continue INTO a subscript
(`self.grid[i], self.grid[j] = ...`); this is the mirror case, continuing OUT of
one into an attribute.

Also check `+=` on the same shape (`xs[0].n += 1`) — augmented assignment splits
by TOKEN across two parsers
([[project_nilpy_augmented_assign_splits_by_token_across_two_parsers]]), so it
may need the arm in a second place.

## Gate

`make test-nilpy` + self-host fixedpoint; a `.npy` diffed against CPython
covering plain `=`, `+=`, a list-literal receiver, a call-result receiver, a
dict receiver, and the bound-name control.
