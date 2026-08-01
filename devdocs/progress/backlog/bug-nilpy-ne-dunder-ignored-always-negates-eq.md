---
summary: "NilPy: a user-defined __ne__ is never consulted — `!=` always negates __eq__, silently returning the wrong value when they differ"
type: bug
track: N
prio: 50
---

# `__ne__` ignored — `!=` always negates `__eq__`

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, predicted by reading `compiler/parser.inc` and then
  confirmed by the CPython differential sweep.

## Measured (self-hosted binary at `3f2c5b915`)

```python
class C:
    def __init__(self, v):
        self.v = v
    def __eq__(self, o):
        return self.v == o.v
    def __ne__(self, o):
        return "NE-CALLED"
print(C(1) != C(2))
```
CPython: `NE-CALLED`. pxx: **`True`.**

## Cause

The `==`/`!=` dispatch (`compiler/parser.inc`, the `op in [tkEq, tkNeq]` block)
resolves **`__eq__` only** and wraps the result in `AN_NOT` for `tkNeq`.
`__ne__` appears **nowhere** in `compiler/**` — confirmed by
`grep -oh '__[a-z_]*__' compiler/*.inc` — so nothing can dispatch it.

## Why it still matters even though `!= == not ==` usually holds

CPython does NOT define `!=` as `not __eq__` when `__ne__` is present; it calls
`__ne__`. Classes that deliberately break the symmetry are exactly the ones this
silently corrupts (three-valued/SQL-style comparisons, NaN-like sentinels,
"always unequal" identity wrappers). The auto-derived case is already correct
and must stay: with **only** `__eq__` declared, CPython derives `!=` as its
negation — measured, and pxx already matches there
(`C(1) != C(1)` → `False`, `C(1) != C(2)` → `True`).

So the fix is narrow: prefer `__ne__` when declared, otherwise keep today's
negate-`__eq__` behaviour.

## Fix shape

In the same block, for `tkNeq`: try `FindUMeth(ci, '__ne__')` first and call it
directly (no `AN_NOT` wrapper — the method's own result is the answer, and it
need not be a Boolean, as the `NE-CALLED` string above shows). Fall back to the
existing negated `__eq__` path.

Mind the pylib-container exclusion that the ordering-dunder fix needed
(`PyRecIsPylibOwnClass`, `compiler/symtab.inc`) — the existing `__eq__` block is
safe only by accident, because it additionally requires `__eq__` to be declared
and pylib's containers declare no such method.

Reflected `__ne__` on the right operand is out of scope here; it belongs with the
general reflected-dunder work in
[[feature-nilpy-arithmetic-dunders-full-protocol]].

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering: `__ne__` declared (it wins, including a non-Boolean result),
only `__eq__` declared (negation still derived), and neither declared (identity).
