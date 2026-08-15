---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`g = (x for x in [1,2]); next(g); list(g)` answers [1, 2] where CPython answers [2] — a genexpr bound to a name is materialised eagerly, so it is re-iterable and `next()` does not advance what a later consumer sees."
---

# A generator expression is not consumed once

```python
g = (x for x in [1, 2])
print(next(g), list(g))     # CPython 1 [2]     pxx 1 [1, 2]
```

Silent. Found 2026-08-15 by a CPython differential sweep of the iterator
protocol, in the pass that fixed
[[bug-nilpy-int-and-float-ignore-their-dunders]].

Single consumption is the observable half of laziness, and NilPy already has it
for every cursor `map`/`filter`/`zip`/`enumerate`/`iter` produce (`TPyIter`,
whose `FEnd` never restarts). A genexpr bound to a NAME is the shape that misses
it: the comprehension lowering builds a LIST and the name holds that list, so
`next()` reads element 0 and the later `list()` walks the same list from the
start.

Note what already works, which bounds the fix: `sum(x for x in xs)` and every
other genexpr consumed IN PLACE is correct, because nothing observes the
container twice.

## Two more things to measure before fixing

- Is `iter(g)` on the materialised list idempotent the way CPython's is (a
  generator's `iter` is itself)?
- An infinite genexpr — `(x for x in itertools.count())` — cannot be
  materialised at all, so it presumably hangs today. Worth confirming: if it
  does, that is the same bug wearing a much louder hat and belongs in this
  ticket's repro list.

The clean shape is for a genexpr in VALUE position to build a `TPyIter` over the
source with the element expression as its mapping, which is what
`pyiter_map`/`pyiter_map_conv` already are — rather than a second lazy
mechanism.

## Gate

`.npy` diffed against CPython: the repro; `next` twice then `list`; a genexpr
passed to a def and consumed there; two consumers of one genexpr (the second
must see nothing); `sum`/`max` over a genexpr consumed in place (unchanged); a
genexpr with a filter clause; and `list(g)` twice.
