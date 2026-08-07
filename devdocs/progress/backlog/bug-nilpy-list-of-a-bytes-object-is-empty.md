---
track: N
prio: 35
type: bug
summary: "`list(b)` on a bytes object answers [] instead of the byte values — silent, and it makes the idiomatic way to inspect to_bytes output show nothing"
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
