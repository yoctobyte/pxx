---
prio: 50
track: N
type: bug
blocked-by: []
---

# `repr()` of a VARIANT holding a user instance answered ''

- **Type:** bug (NilPy, **silent wrong value**) — **Track N**
- **Found:** 2026-08-09, running a REALISTIC program (a record parser with
  classes, exceptions and sorting) against CPython — not by sweeping an API
  surface. It needed the combination to show.
- **Status:** FIXED the same session.

```python
xs = [R(1)]
print(repr(R(1)))     # correct  — a statically class-typed value
print(repr(xs))       # correct  — the container path
print(repr(xs[0]))    # ''       — an ELEMENT
print(f"{xs[0]!r}")   # ''
```

## Cause — two variant reprs, and the wrong one was the entry point

`pyvar_repr` knew about objects (None, callables, the pylib containers, a user
class's `__repr__`) and then handed the rest to `pyrepr_of`. `pyrepr_of` quoted
a string and gave everything else to `pystr_of`, which answers `''` for a user
instance — and `pyrepr_of` was what `repr()` and the f-string `!r` hole actually
reached. The container case looked right only because `pylist_repr` goes through
`pyvar_repr`.

Classic two-mechanisms-for-one-concept: the fix inverts the layering so
`pyvar_repr` is the single implementation and `pyrepr_of(Variant)` forwards to
it, with the string/char quoting moved to `pyvar_repr`'s tail so the two cannot
drift.

**The f-string is what makes this more than a one-line fix.** `!r` lowers
straight to `pyrepr_of` (`PyFStrSwapLastCall` swaps `pystr_of(` for
`pyrepr_of(`), so fixing `repr()` alone would have left `f"{obj!r}"` empty — the
same bug through a second door, which is exactly the shape this codebase keeps
being bitten by.

## Verified
`test/test_nilpy_repr_of_variant_object.{npy,expected}` (`.expected` from
CPython): the same object reached as a static value, an element, a bound name, a
container, a comprehension, an f-string `!r` and a function parameter, plus
scalar and nested controls. `gate.sh quick` GREEN, and the repr/format/container
test families re-diffed against CPython (the four that differ are identical on
the PINNED binary — the recorded-divergence tests).
