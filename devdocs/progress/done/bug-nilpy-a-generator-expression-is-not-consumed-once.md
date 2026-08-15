---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`g = (x for x in [1,2]); next(g); list(g)` answers [1, 2] where CPython answers [2] — a genexpr bound to a name is materialised eagerly, so it is re-iterable and `next()` does not advance what a later consumer sees."
status: done
owner: claude-AN
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

## Resolution (2026-08-15)

`PyParseParenComp`'s value is now a CURSOR over the materialised elements
(`pyiter_gen`), not the list itself, so `next()` advances what a later consumer
sees and a second consumer sees nothing. Only the PARENTHESISED form takes this
road: a bare genexpr consumed in place (`sum(x for x in xs)`) comes through
`PyParseCompExprValue`, where nothing observes the container twice and the
builtins want a list.

`pyiter_gen` is a list cursor with an `FIsGen` FLAG, not a new `PYITER_GEN`
kind, precisely because the advance is a list cursor's — identical behaviour.
A new kind would have to be added to every site that tests `FKind`, and the one
that got missed is where the next bug would live. The flag has exactly one
reader: `pyiter_typename`, so `type(g).__name__` answers `generator`.

### The measurement that changed the shape of the fix

Wrapping the value turned `test_nilpy_bare_genexpr_arguments` RED at
`C().two(10, (x for x in xs))` — 10 instead of 16. Not the genexpr: **`sum`,
`any` and `all` had no VARIANT arm**, so a call with a variant argument fell to
the `TPyList` overload and hard-CAST it. Measured on the pre-change compiler,
which is what makes it pre-existing rather than mine:

| written | CPython | pxx before |
| --- | --- | --- |
| `def s(v): return sum(v)` … `s([1,2,3])` | 6 | 6 |
| `s(range(4))` | 6 | **0** |
| `s(map(lambda x: x, [1,2,3]))` | 6 | **SIGSEGV** |

`max`, `min`, `len` and `tuple` already had the arm; these four did not. That
asymmetry IS the bug — the same "one concept, N sites, the missed one is where
it lives" shape as the star work earlier today — so the four arms landed here
rather than as a separate microfix, each routing through `pylist_v` (a str
spreads, a dict gives its keys, a cursor DRAINS, a user `__iter__` is walked).

### Still open, deliberately

The elements are still materialised EAGERLY, so an infinite genexpr is still
not expressible and side effects still happen at construction. Making it truly
lazy means building a `TPyIter` whose mapping is the element expression — i.e.
desugaring to `map`/`filter` over lifted lambdas, which is the lambda lifter's
machinery over a token span. Filed as
[[feature-nilpy-a-genexpr-is-lazy-not-materialised]]; the observable half
(single consumption) is what this ticket asked for and what shipped.

`sorted` has no Variant arm either, but it also has no `TPyList` overload this
path reaches, so it is left alone rather than changed on a guess.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v335.
`test/test_nilpy_genexpr_is_consumed_once.npy`, byte-identical to CPython:
`next` then `list`, `next` twice then the rest, two consumers, a for-loop that
exhausts it, a filter clause, tuple-unpack from one, a genexpr passed to a def,
`sum`/`max`/`sorted`/`join`/`any`/`all` over a parenthesised one, `map` over
one, `type(...).__name__`, and the variant-arm shapes (a range and a map cursor
through a parameter). Re-checked the fourteen comprehension/genexpr tests.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
