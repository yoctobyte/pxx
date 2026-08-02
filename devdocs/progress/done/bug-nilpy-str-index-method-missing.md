---
track: N
prio: 50
type: bug
---

# `str.index()` / `str.rindex()` were missing

- **Type:** bug (missing str method — loud) — **Track N**
- **Found and FIXED:** 2026-08-02, by a differential sweep against the CPython
  oracle.

## Measured

```python
"Hello World".index("W")     # CPython 6
```
```
error: Nil Python: unsupported str method .index() (have: upper, lower, strip,
lstrip, rstrip, startswith, endswith, find, isspace, isdigit, isalpha, isalnum,
isupper, islower, format, join, split, rsplit, partition, rpartition,
splitlines, replace, count, rfind, title, capitalize, swapcase, casefold,
ljust, rjust, center, zfill, removeprefix, removesuffix)
```

32 methods supported, `index` not among them — and `rindex` likewise.

## Why it matters

`index` is not a synonym for `find`: it **raises `ValueError`** when the
substring is absent, where `find` returns `-1`. That is the entire reason both
exist, and it is the form you use when absence is a bug rather than a case to
handle. Code written that way did not compile at all.

## Fix

`pystr_index` / `pystr_index_from` / `pystr_rindex` in pylib, each delegating to
the corresponding `find` and raising `ValueError('substring not found')` on
`-1`. Added to `PyStrMethodInfo` reusing the existing `-3` argument shape
(substring plus optional start), so `index(sub)` and `index(sub, start)` both
work with no new plumbing.

## Verified

`test/test_nilpy_str_index.npy`, wired into `make test-nilpy`, byte-identical to
CPython: `index`/`rindex` hits, `index` with a start offset, `find`/`rfind`
returning `-1` for the same absent needle as a contrast, and all three
`ValueError` paths caught with `try/except`.

## Context worth keeping

This was the ONLY gap in that sweep — the other 19 lines of the string-method
and formatting surface (count/find/rfind/startswith/endswith/case
conversions/replace/strip/split/join/is*/ord/chr/format/f-strings/`%` specs/
bin/hex/oct) agreed with CPython exactly. The string surface is in good shape.
