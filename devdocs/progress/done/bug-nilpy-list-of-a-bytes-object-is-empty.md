---
track: N
prio: 35
type: bug
summary: "`list(b)` on a bytes object answers [] instead of the byte values — silent, and it makes the idiomatic way to inspect to_bytes output show nothing"
status: done
owner: claude-AN
---

# `list(<bytes>)` is empty

```python
v = 300
b = v.to_bytes(8, "little", signed=True)
print(list(b))          # CPython [44, 1, 0, 0, 0, 0, 0, 0]    pxx []
```

Indexing and `len()` are correct — `len(b)` is 8 and `b[0]`/`b[1]` are 44/1 —
so the object is right and only `list()` of it is empty. Silent: an empty list
is a plausible answer, and `list(x)` is how you look at a bytes value.

## Pre-existing

Identical on `stable_linux_amd64/default/pinned`. Found 2026-08-07 while fixing
[[bug-nilpy-to-bytes-on-a-variant-receiver-does-not-compile]] — the first draft
of that test used `list(b)` to dump the bytes and reported this instead, so the
test now indexes in a loop and says why.

## Where to look

`pylist_of` / whatever `list(x)` lowers to, for a `TPyBytes` argument: bytes is
a distinct pylib container (`pybytes_repr` exists beside `pylist_repr` and
`pydict_repr`), so the list constructor most likely has arms for TPyList/TPyDict
and falls through to an empty result for TPyBytes rather than iterating it.
Check `tuple(b)` and `set(b)` and a `for x in b` loop at the same time — if the
iteration protocol is what is missing, they will all be wrong together and that
is the thing to fix, not `list` alone.

## Gate

Per-fix loop, plus a `.npy` covering `list(b)`, `tuple(b)`, `for x in b` and
`b[i]`/`len(b)` (which already work), diffed against CPython.

## Log
- 2026-08-08 — resolved, commit c22e43e6b.

## Fixed 2026-08-08

`list(b)`/`tuple(b)` now have TPyBytes arms in `compiler/builtin/pylib.pas`,
and the two variant renderers (`pylist_v`, `list(const v: Variant)`) route a
tag-7 TPyBytes payload to the same one — so bytes erased into an untyped
parameter or a container element behave like the static form.

The "where to look" guess was right about the shape and wrong about the
cause: `list(b)` was not falling through to an empty result, it was
RESOLVING to `list(l: TPyList)` — a TPyBytes handle in a list-typed
parameter, whose `count` read the wrong field and answered 0. Which is why
it was silent rather than an error.

The iteration protocol was NOT the missing piece: `for x in b`, `len(b)` and
`b[i]` all already agreed with CPython and still do. `tuple(b)` was the loud
sibling — a compile-time "no overload of tuple matches" — fixed in the same
pass so the two spellings cannot drift apart.

Test: `test/test_nilpy_list_of_bytes.npy`, wired into `make test-nilpy`,
diffed against CPython (exact match, including the empty-bytes case and both
variant paths).
