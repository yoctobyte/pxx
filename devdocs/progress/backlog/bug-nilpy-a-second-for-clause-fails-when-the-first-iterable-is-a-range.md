---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`[x + y for x in range(2) for y in [10]]` is 'undefined variable (y)' — a two-for comprehension works only when the FIRST clause iterates a list; a range() there takes a fast path that never binds the second clause's name. `for x in <list> for y in range(...)` is fine, so it is the first iterable alone that decides"
---

# A second `for` clause fails when the FIRST iterable is a `range()`

- **Type:** bug (compile error on ordinary code) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython.
- **Related:** [[bug-nilpy-nested-for-comprehension-not-supported]] (done) made
  the two-for comprehension work; this is the arm it did not reach.

```python
print([x + y for x in range(2) for y in [10]])     # error: undefined variable (y)
print([x + y for x in [10] for y in range(2)])     # fine -> [10, 11]
```

## The boundary — the FIRST iterable decides, and only it

| comprehension | result |
| --- | --- |
| `[x + y for x in range(2) for y in [10]]` | **error: undefined variable (y)** |
| `[x + y for x in range(2) for y in range(3)]` | **error: undefined variable (y)** |
| `[(x, y) for x in range(2) for y in range(2)]` | **error: undefined variable (y)** |
| `[[x, y] for x in range(2) for y in range(2)]` | **error: undefined variable (y)** |
| `[x for x in range(2) for y in range(2)]` | **error: unexpected token** |
| `[x + y for x in [10] for y in range(2)]` | ok — `[10, 11]` |
| `[x * 10 + y for x in [1,2] for y in [3,4]]` | ok — `[13, 14, 23, 24]` |
| `[x + y for x in rng for y in rng]` (a NAME holding a list) | ok — `[0, 1, 1, 2]` |
| `[c for r in rows for c in r]` (the flatten idiom) | ok |

So the second clause is parsed and lowered correctly in general; a `range()` in
the FIRST clause routes the comprehension onto a different (counted) path that
consumes the rest of the header without ever binding the second target. The
element expression only changes WHICH error you get — using the second name
gives "undefined variable", not using it gives "unexpected token", which is the
tell that the header, not the element, is what got mis-parsed.

## Why it matters

`for i in range(n) for j in range(m)` is the plainest way to write a nested
iteration in a comprehension — grids, pair tables, index products — and
`range()` is the first iterable anyone reaches for. The workaround (bind the
range to a name first, or use a list) is not discoverable from the message.

## Where to look

The `range()` fast path in the comprehension lowering (pyparser.inc, the
comprehension header parse — the same code the flatten fix in
[[bug-nilpy-nested-for-comprehension-not-supported]] taught about a second
clause). Expect a straight case of one shape's handler predating the multi-
clause support: the fix is to make the counted-range arm loop over the
remaining `for`/`if` clauses exactly as the general arm does, not to special-
case two clauses. Check the `if` filter on the same path while there —
`[x for x in range(4) if x > 1]` works, but `for x in range(2) for y in ... if
...` is worth a row in the test.

## Gate

A `.npy` diffed against CPython: every row of the table above, plus a
three-clause comprehension, a filter on each clause, a dict and a set
comprehension with the same header, and the tuple-element form (the shape that
found this).
