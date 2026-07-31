---
track: N
prio: 35
type: bug
---

# `list.sort(key=...)` (the in-place METHOD) is missing — `sorted()` works fine

```python
rows = [(1, 3), (2, 1), (3, 2)]
rows.sort(key=lambda r: r[1])
print(rows)
```

```
error: Nil Python: TPyList has no method sort
```

Found 2026-07-31 while re-verifying [[feature-nilpy-lambda]] (closed — real
lambda values already work). The standalone `sorted(rows, key=lambda r:
r[1])` FUNCTION already works correctly (diffed against CPython, matches
exactly) — this is specifically the in-place `.sort()` METHOD on `TPyList`
that has no implementation at all, not a lambda/key= problem.

## Shape of a fix

`sorted()`'s own implementation (pyeval.pas has a `sorted(l: TPyList; key:
Pointer = nil; reverse: Boolean = False): TPyList` per this session's
earlier reading of that file) already does the real work — an in-place
`.sort()` should be a thin wrapper: call the same comparison/key logic but
write the result back into the SAME `TPyList` instead of returning a new
one (Python's `list.sort()` returns `None` and mutates in place, unlike
`sorted()`).

## Partially fixed (this session) — plain `.sort()` only

Added `TPyList.sort` (pylib.pas) as a genuine method — no-key insertion sort
using `pyvar_gt`, mutating `Self` in place (confirmed: a second reference to
the same list object sees the sort, matching Python's identity guarantee).
Diffed against CPython for both numbers and strings; exact match.

`key=`/`reverse=` NOT done: the original "shape of a fix" assumption (thin
wrapper around `sorted()`) turned out not to work — `sorted()`'s key=
dispatch goes through `PyCallKey1`, which lives in `pyeval.pas`, and
`pyeval` `uses pylib` (not the reverse), so `pylib.pas` cannot call back
into it. A real `key=`/`reverse=` implementation needs either moving the
generic-callable-invoke primitive down into `pylib.pas` (shared by both
units) or a frontend-level rewrite of `.sort(key=...)` into a build-then-
swap sequence around the existing `sorted()` — either is more than this
pass's scope. `xs.sort(key=...)` still fails to PARSE (a compile error,
not a crash — `sort` genuinely takes no parameters today), which is the
safe direction to fail in the meantime.

## Gate

`make test-nilpy` + self-host byte-identical, plus `.sort()` with no key,
with `key=lambda`, and with `reverse=True`, diffed against CPython — and
confirm the list identity is preserved (same object, mutated) the way
Python's own `.sort()` guarantees.
