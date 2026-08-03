---
summary: "NilPy: a user-defined __ne__ is never consulted — `!=` always negates __eq__, silently returning the wrong value when they differ"
type: bug
track: N
prio: 50
status: done
owner: agent-AN
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

## FIXED 2026-08-01

`compiler/parser.inc`: a `tkNeq` arm placed BEFORE the existing `__eq__` block —
if the left operand's class declares `__ne__`, call it and return its result
as-is (no `AN_NOT` wrapper, since CPython returns whatever `__ne__` yields and
it need not be a Boolean). Falls through to the old negated-`__eq__` path
otherwise, so the auto-derived case is unchanged.

Carries the `PyRecIsPylibOwnClass` exclusion (`compiler/symtab.inc`). The
existing `__eq__` block is safe without it only by accident — it additionally
requires `__eq__` to be declared, and pylib's containers declare no such method
— so the new arm does not rely on that coincidence.

`test/test_nilpy_dunder_ne.npy`, byte-identical to CPython: a class where
`__ne__` and `not __eq__` deliberately DISAGREE (the only way to prove which was
consulted, and it returns a non-Boolean), a class with only `__eq__` (negation
still derived), a class with neither (identity), and list `!=` (must stay
content equality, not reach the new arm).

Gate: `make test-nilpy` + self-host fixedpoint byte-identical.

### Out of scope, unchanged

Reflected `__ne__` on the RIGHT operand — belongs with the general reflected
work in [[feature-nilpy-arithmetic-dunders-full-protocol]], where all seven
reflected forms are measured broken.

Static receivers only, like every other compile-time dunder dispatch: `a != b`
where either side arrives as an untyped parameter is a variant and needs
[[decide-nilpy-runtime-dunder-dispatch-mechanism]].

## Re-verified 2026-08-03 at HEAD — was fixed but never moved out of backlog/

The fix and its gate test both landed on 2026-08-01; only the ticket's file
move was missed, so it kept surfacing in the ready queue as open work.

Re-measured against a self-hosted binary at HEAD rather than re-read: this
ticket's own reproducer prints `NE-CALLED`, matching CPython, and
`test/test_nilpy_dunder_ne.npy` is present and registered in the Makefile —
`__ne__` wins where it disagrees with `not __eq__`, the derived negation still
holds with only `__eq__`, identity holds with neither, and list `!=` still
compares by content. Closed on the measurement, not on the write-up.

Out-of-scope items above are unchanged and stay with their own tickets:
reflected `__ne__`, and a variant (non-static) receiver, which needs
[[decide-nilpy-runtime-dunder-dispatch-mechanism]].

## Log
- 2026-08-03 — resolved, commit PENDING-COMMIT.
