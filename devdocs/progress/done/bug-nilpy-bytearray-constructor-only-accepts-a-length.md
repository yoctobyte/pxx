---
track: N
prio: 45
type: bug
summary: "bytearray() only has () and (Integer) overloads — bytearray(b\"abc\") and bytearray([1,2,3]) are compile errors, so a bytearray cannot be built from data"
status: done
owner: claude-AN
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


## Resolved 2026-08-04 — the two the ticket named, with both traps it flagged

`bytearray(b: TPyBytes)` and `bytearray(l: TPyList)` added to `pylib.pas`, which
is all this needed — `TPyBytes` was already complete, only construction was
missing. Both hazards the ticket called out are handled and pinned by a row:

- **COPY, not alias.** `bytearray(bytes)` allocates and copies. The test mutates
  the copy and checks the SOURCE is unmoved (`src[0]` stays 120 while `b[0]`
  becomes 65) — returning the same object would have been a silent aliasing bug,
  and the whole point of the call is usually a mutable copy of an immutable
  bytes.
- **Out-of-range RAISES.** An element outside 0..255 raises `ValueError`
  (catchable), not a truncation to a byte. A truncation here would put a wrong
  VALUE in a buffer, which is the failure mode this type is used to avoid.

`nil` receivers yield an empty buffer rather than faulting, matching how the
rest of the container surface treats a missing object.

Not added: the `str`-with-encoding form. `bytearray("abc", "utf-8")` is a
different question (this frontend is byte-string throughout — see
`bug-nilpy-non-ascii-string-surface-measured`) and adding it here would have
smuggled an encoding decision into a constructor fix.

### Verified

`test/test_nilpy_bytearray_ctor.npy`, wired into `make test-nilpy`: both new
forms, the alias check, an empty list, the two forms that already worked, and
the `ValueError`. Diffed against CPython, identical. `tools/gate.sh quick`
GREEN, self-host byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit 3a540a4af.
