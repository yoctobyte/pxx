---
track: N
prio: 60
type: bug
---

# A set LITERAL keeps duplicates; `set().add()` removes them

```python
s = {1, 2, 2, 3}
print(len(s))          # CPython: 3    pxx: 4
```

```python
s = set()
s.add(1)
s.add(2)
s.add(2)
print(len(s))          # CPython: 2    pxx: 2      <- correct
```

A set is backed by TPyList and `add` appends only when the element is absent —
that IS the set contract as designed (see the `set` branch of PyAnnTypeTermAt).
The literal `{...}` does not go through `add`; it builds the list directly, so
duplicates survive. So the design is intact and one construction path skips it.

Silent, and the shape it breaks is the one sets are used for: `{...}` as a
membership/dedup set, then `len()` or an `in` scan over it.

Found by the data-structure sweep against CPython (aliasing, `copy`, nested
lists and dicts, tuple unpacking, swap, unpacking in a for-loop, `join`,
`reversed`, nested indexing) — everything else there matched, apart from
[[bug-nilpy-sorted-over-tuples-or-lists-fails]].

## Gate

`make test-nilpy` + self-host byte-identical, plus set literals with duplicate
ints, strings and mixed types, and a literal followed by `add` of an element it
already contains.

## Log
- 2026-07-30 — resolved, commit 16c94927b.
