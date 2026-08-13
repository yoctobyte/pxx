---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`[x + y for x in xs if x > 0 for y in range(2)]` — an `if` BETWEEN two for-clauses — is 'undefined variable (y)' on BOTH comprehension paths (container and range). A filter after the LAST clause is fine, and so are two clauses with no filter; it is only the interleaved position that fails"
---

# A filter BETWEEN two `for` clauses is not supported

- **Type:** bug (compile error on ordinary code) — **Track N**
- **Found:** 2026-08-13, while fixing
  [[bug-nilpy-a-second-for-clause-fails-when-the-first-iterable-is-a-range]] —
  it is the one row of that ticket's matrix that stayed red, and it was already
  red on the CONTAINER path, so it is a separate defect rather than a piece of
  that one.

```python
print([x + y for x in [0, 1, 2] if x > 0 for y in range(2)])
# CPython [1, 2, 2, 3]
# pxx     error: undefined variable (y)  near: __py_cv6_0  y >>> for __py_cv6_0
```

## The boundary — the POSITION of the filter, on either path

| comprehension | result |
| --- | --- |
| `[x + y for x in xs for y in ys]` (no filter) | fine |
| `[x + y for x in xs for y in ys if y > 1]` (after the LAST clause) | fine |
| `[x for x in xs if x > 1]` (one clause, filtered) | fine |
| `[x + y for x in xs if x > 0 for y in ys]` (BETWEEN) | **error** |
| the same with `range()` in either clause | **error** |

CPython allows a filter after every clause, and the natural reading —
"filter the outer loop before entering the inner one" — is also the efficient
one, which is why the position is used.

## Where to look

Both paths (`PyParseForIn`'s comprehension arm and `PyParseFor`'s counted-range
arm) treat the filter as a suffix: they parse the element expression, then look
for a single trailing `if` and wrap the append in it. A clause-position filter
needs the filter to wrap the REST OF THE HEADER instead — the recursion into
the next clause has to happen INSIDE the AN_IF, not after it.

The two-clause recursion landed in
[[bug-nilpy-a-second-for-clause-fails-when-the-first-iterable-is-a-range]]
(and, for containers, in [[bug-nilpy-nested-for-comprehension-not-supported]]),
so the shape to add is: at the point where the header continues, if the next
token is `if`, parse the condition, then recurse for whatever follows and wrap
the recursion's body in the filter. Both paths need it — fixing one arm of a
double case is what `devdocs/dev/normalise-dont-special-case.md` is about, and
this bug is the second time this pair has diverged.

## Gate

A `.npy` diffed against CPython: the interleaved filter with a container first
clause and with a `range()` first clause, a filter on BOTH clauses, a filter
between three clauses, and the already-working suffix-filter rows as controls.
