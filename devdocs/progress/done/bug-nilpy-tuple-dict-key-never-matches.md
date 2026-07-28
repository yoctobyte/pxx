---
track: N
prio: 65
type: bug
---

# A tuple used as a dict KEY never matches on lookup

```python
d = {}
d[(1, 2)] = "a"
print(d[(1, 2)])
```

CPython: `a`. pxx: **KeyError**.

Storing works; the lookup does not find it. A tuple is a TPyList here, so the
key comparison is presumably by identity (or by a hash of the handle) rather
than by CONTENTS — the same distinction that
`bug-a-nilpy-container-equality-compares-identity` fixed for the `==` operator
and that `pylist_eq` implements. The dict's own key path did not get it.

Coordinate keys are ordinary Python (`grid[(x, y)]`, memo tables, caches keyed
by a pair), so this is worth fixing beyond the case that surfaced it.

## Where it surfaced

songformatter's `render_backend.py:135` writes `px[ix, iy]` — PIL pixel access,
a 2-D subscript that Python turns into a tuple key. The PARSE of that form on a
dynamically-typed receiver was a separate gap and is fixed; this ticket is only
about the key never matching. That code is unreachable under pxx (PIL is
absent), so nothing is blocked on it today.

## Gate

`make test-nilpy` plus a `.npy` storing and reading tuple keys, including two
distinct tuples with equal contents, diffed against CPython.

## Log
- 2026-07-28 — resolved, commit HEAD.

## Fix

`PyVarHashKey` (pylib.pas) gained a VT_OBJECT arm for a TPyList payload: the
hash is now a sequence hash over the ELEMENTS, seeded by the length and
recursing through `PyVarHashKey`, so it mirrors `PyVarEq`'s element-wise
compare arm for arm. Any other object keeps the identity hash, which is what
PyVarEq's identity compare for non-lists requires.

Verified against CPython: the ticket's repro, a 3x3 coordinate grid keyed by
`(x, y)`, keys built fresh at lookup vs stored from a variable, a nested tuple
key, mixed element types in one key, `1` / `"1"` / `(1,)` as distinct keys in
one dict, overwrite-in-place, iteration, `dict.get` with a tuple key, and a
200-key stress with 231 membership probes. `test/test_nilpy_tuple_dict_key.npy`
covers the set and is registered in `test-nilpy` / `test-core`.

Found while testing it, filed separately:
[[bug-nilpy-method-chaining-on-a-call-result]],
[[bug-nilpy-str-of-tuple-is-empty]].
