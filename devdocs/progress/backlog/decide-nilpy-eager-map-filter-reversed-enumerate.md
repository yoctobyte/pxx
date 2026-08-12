---
track: U
prio: 40
type: decide
blocked-by: []
summary: "map/filter/reversed/enumerate return LISTS, not lazy iterators — so `print(map(str, [1]))` prints `['1']` where CPython prints `<map object at 0x…>`. Every ordinary use agrees; laziness-dependent code does not. Decide: divergence note (my recommendation), or real iterator objects"
---

# Decide: eager `map` / `filter` / `reversed` / `enumerate`

- **Track U** (decision) — raised 2026-08-12 from the builtin sweep in
  [[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]].

## The fact

```python
print(map(str, [1]))        # pxx: ['1']   CPython: <map object at 0x7e49b4d06080>
print(filter(None, [0, 1])) # pxx: [1]     CPython: <filter object at 0x...>
print(reversed([1, 2]))     # pxx: [2, 1]  CPython: <list_reverseiterator object ...>
print(enumerate([1], 1))    # pxx: [(1,1)] CPython: <enumerate object at 0x...>
```

NilPy evaluates them eagerly and hands back a list. Every ordinary use agrees
with CPython — `list(map(...))`, iterating one in a `for`, comprehending over
it, `len(list(...))`, `sorted(...)` — because those all consume the whole thing
anyway.

## Why it is a real fork and not just a printing nit

Three shapes of working CPython code CAN observe the difference:

1. **Printing or repring one directly** (above) — harmless but visible, and the
   kind of thing a doctest or a logged debug line catches.
2. **An unbounded or expensive source**: `for x in map(f, huge)` in CPython
   never materialises the list; here it does, so memory and the cost of `f`
   both change, and an infinite generator source would hang.
3. **Single consumption**: a CPython iterator is exhausted after one pass, so
   `it = map(f, xs); list(it); list(it)` gives `[...]` then `[]`. Here both
   passes give the full list — NilPy is *more* forgiving, which by the upward-
   compatibility rule is a feature, not a defect.

Point 2 is the one that can make working code fail rather than differ.

## The options

**A — Document it as a divergence (recommended).** Add it to
`devdocs/dev/nilpy-semantics-divergences.md` with the three observable shapes
spelled out. Cheap, honest, and consistent with how the mutable-tuple call was
made. The cost is that shape 2 stays a real (if rare) failure mode, and the
first person to hit it debugs it from scratch unless the page is easy to find.

**B — Implement real lazy iterators.** Correct, and it also gives `iter()` /
`next()` somewhere to live (both are absent —
[[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]]). But it needs
an iterator protocol object in pylib, a frontend that can consume one in every
`for`/comprehension position, and a `__next__` dispatch — comparable in size to
the generator work, and it would touch the hottest loop lowering in the
frontend.

**C — Split the difference:** keep the eager list, but make `print`/`repr` of
one show CPython's `<map object at 0x…>` shape. This is the worst option and is
named only to be rejected: it makes the value LIE about what it is, so shape 3
gets more surprising, not less.

## Recommendation

**A**, plus a line in the divergences page for shape 2 specifically ("a map over
an unbounded or expensive source is materialised here"), and revisit B if and
when generators land — the two want the same machinery, and doing them together
is much less work than doing them apart.
