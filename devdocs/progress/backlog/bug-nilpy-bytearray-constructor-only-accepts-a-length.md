---
track: N
prio: 45
type: bug
summary: "bytearray() only has () and (Integer) overloads — bytearray(b\"abc\") and bytearray([1,2,3]) are compile errors, so a bytearray cannot be built from data"
---

# `bytearray()` cannot be built from data

- **Type:** bug / missing builtin overloads (NilPy) — **Track N**
- **Found:** 2026-08-02, while sweeping extended slices against CPython
  (alongside [[bug-nilpy-type-name-reports-the-internal-pascal-class]]).
- **Loud**, not silent: a compile error naming the available overloads.

```python
bytearray(b"abc")     # error: no overload matches
bytearray([1, 2, 3])  # error: no overload matches
```
```
  candidates:
    bytearray()
    bytearray(Integer)
```

So a `bytearray` can only be created EMPTY or ZERO-FILLED to a length. Every
way of getting actual bytes into one at construction is missing. CPython's
constructor takes: a `bytes`/`bytearray` (copy), an iterable of ints, a str with
an encoding, or an int (zero-fill, the one we have).

## Why it is worth fixing

`TPyBytes` already exists and is well covered — slicing, `pybytes_setslice`,
`find`, `len`, and the extended-slice work all operate on it. The gap is purely
in getting one INITIALISED, which makes the whole type awkward to reach from
ordinary Python: the natural spelling `bytearray(b"...")` is exactly the one
that fails. `b"..."` literals themselves work fine.

The two worth adding first are the ones real code writes:

- `bytearray(b: TPyBytes)` — a COPY, not an alias. Getting this wrong (returning
  the same object) would be a silent aliasing bug, since the point of the call
  is usually to get a mutable copy of an immutable `bytes`.
- `bytearray(l: TPyList)` — an iterable of ints, raising `ValueError` for an
  element outside 0..255 as CPython does, rather than truncating.

`bytearray(s, encoding)` can wait; `pystr_encode` already exists and would back it.

## Gate

A `.npy` diffed against CPython: construct from a `bytes` literal and from a
list of ints, mutate the result, and confirm the source is unchanged (the copy
semantics); plus the out-of-range element raising.
