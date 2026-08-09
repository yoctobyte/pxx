---
prio: 50
track: N
type: bug
blocked-by: []
---

# `dict.update(<variant>)` SEGFAULTED

- **Type:** bug (NilPy, **crash**) — **Track N**
- **Found:** 2026-08-09, running a realistic config reader against CPython.
- **Status:** FIXED the same session.

```python
DEFAULTS = {"host": "localhost"}

def merged(sec):
    m = dict(DEFAULTS)
    m.update(sec)        # SIGSEGV
    return m
```

`m.update({"k": v})` with a LITERAL was always fine. That is what kept this out
of every API sweep: it needs the value to arrive through a PARAMETER, and
`merged = dict(DEFAULTS); merged.update(section)` is the ordinary shape.

## Cause

`TPyDict.update` has two typed overloads — `update(TPyList)` for an iterable of
pairs and `update(TPyDict)` for a mapping. An unannotated parameter is a
**VARIANT**, which matches neither, and it resolved to the `TPyList` arm: a
`TPyDict` was then walked as a list.

## Fix

A third `update(const v: Variant)` overload that dispatches on the runtime tag
and delegates to whichever typed arm the value actually is, raising `TypeError`
for anything else (CPython's own answer for a non-mapping, non-iterable).

Both argument kinds are asserted THROUGH A PARAMETER, since a fix that sent
both down one arm would still pass a mapping-only test.

## Verified
`test/test_nilpy_dict_update_variant.{npy,expected}` (`.expected` from CPython):
a mapping and an iterable of pairs through a parameter, an empty mapping, a
literal, the loop shape it was found in, and the statically-typed spellings that
always worked as controls. `gate.sh quick` GREEN; the dict test family re-diffed
against CPython.

## Noted while fixing
The same realistic program then hit
[[bug-nilpy-set-augmented-union-does-nothing]] (`a |= set(...)` silently does
nothing), filed separately.
