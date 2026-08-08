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

## 2026-08-09 — re-measured; and the "needs a frontend rewrite" half is WRONG

State at HEAD is exactly as the partial-fix note says: `xs.sort()` works,
`xs.sort(key=...)` and `xs.sort(reverse=True)` are parse errors
(`near: rows sort key >>> lambda r`).

The blocker as stated is **real**: `sorted(l, key, reverse)` and `PyCallKey1`
are both in `pyeval.pas`, and `pyeval uses pylib`, not the reverse — so
`TPyList.sort` in `pylib.pas` genuinely cannot call up to them. Verified, not
assumed.

But the note's second option — *"a frontend-level rewrite of `.sort(key=...)`
into a build-then-swap sequence"* — overstates the work. **Keyword binding is
automatic once the callee declares the parameters.** `PyKwArgIndex`
(`pyparser.inc` ~5293) resolves `name=` against the CALLEE's declared parameter
names, which is exactly why `sorted(l, key=f, reverse=True)` already works with
no per-call special case: `sorted` declares `key: Pointer = nil; reverse:
Boolean = False`. The parse error above is not a kwarg-parsing gap at all — it
is simply that `TPyList.sort` declares no such parameters.

So the remaining work is smaller than recorded:

1. `reverse=` needs **nothing but pylib**: declare `reverse: Boolean = False` on
   `TPyList.sort` and honour it. No callable, no cross-unit call. This half can
   land on its own.
2. `key=` needs the callable, and the two honest routes are (a) a function-
   pointer hook variable in `pylib` that `pyeval` installs — sound because a
   `key=` argument IS a callable and therefore already pulls `pyeval` in — or
   (b) a free `pylist_sort_inplace(l, key, reverse)` in `pyeval` that the
   frontend rewrites `.sort(...)` to, which then gets kwarg binding for free by
   the same rule. Check whether `pyeval` has an initialisation section that
   always runs before choosing (a).

Not started this session: route (b) touches the pylib-container method-call site,
which is in `parser.inc` (Track A shared ground), and sole-A could not be
confirmed. Route (a) and the `reverse=`-only half both stay inside `pylib.pas`
and are pickable without that guard.

Cross-reference: [[feature-nilpy-list-sort-inplace-key-reverse]] covers the same
ground; these two should be merged or one closed as a duplicate.
