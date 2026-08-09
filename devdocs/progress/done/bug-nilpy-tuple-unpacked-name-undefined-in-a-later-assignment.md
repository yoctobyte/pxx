---
prio: 50
track: N
type: bug
blocked-by: []
---

# A tuple-unpacked name is "undefined" in a later assignment's RHS

- **Type:** bug (NilPy, valid CPython refused) — **Track N**
- **Found:** 2026-08-09, same realistic-program run as
  [[bug-nilpy-repr-of-a-variant-holding-an-object-is-empty]].
- **Status:** FIXED the same session.

```python
def pair():
    return [3, 1], ["e"]

a, b = pair()
print(len(a))      # fine
c = a              # error: undefined variable (a)
```

`rows, errs = parse(text)` followed by `by = sorted(rows, key=...)` is how the
shape shows up in real code, and that is where it was found.

## Cause

`PyCollectModuleLocalsAST`'s depth-0 scan recognises a target only as
`ident =`. For `a, b = ...` the token after the name is a COMMA, so the targets
were never registered at all. A later BARE ASSIGNMENT's right-hand side IS
trial-parsed by that pre-pass, and the trial parse died on the unknown name.

`len(a)` worked because only a bare assignment's RHS is trial-parsed — that
asymmetry is what made the error hard to place: the same name is fine one line
earlier.

## Fix

A tuple-unpack target list (`ident (, ident)+ =`) at a statement boundary now
declares its names as `tyVariant`. Identifiers only: `d[k], x = ...` binds
through a subscript rather than declaring a name, so it is left alone.

`tyVariant` is both the honest and the conservative answer — the elements of an
arbitrary unpack have no token-visible type, and trial-parsing the RHS is
precisely what this pre-pass must not do at a name it cannot yet see. It widens
rather than asserts, and the real parse still types the binding properly. All
that is required is that the name RESOLVES.

## Verified
Covered by `test/test_nilpy_repr_of_variant_object.npy` (unpack, then an alias
assignment, then a `sorted(..., key=...)` over the unpacked name).
`gate.sh quick` GREEN.
