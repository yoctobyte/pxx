---
track: N
prio: 35
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "`hasattr(e, \"args\")` answered False about a property the next line reads fine — hasattr consulted fields and methods but not PROPERTIES. Fixing it alone made getattr RAISE for a name hasattr had just approved, so getattr learned to build the property read too."
---

# `hasattr` is blind to a property

```python
e = KeyError("k")
print(e.args)                 # ('k',)  — reads fine
print(hasattr(e, "args"))     # CPython True    pxx False
```

Found 2026-08-15 by a CPython differential sweep of exception semantics — the
only divergence in a 18-line probe that otherwise agreed exactly (try/else/
finally, re-raise, tuple except, base-class catch, exception attributes,
finally-with-break/continue).

Silent and in the worst direction: `hasattr` is Python's duck-typing primitive,
so a False sends `if hasattr(x, "args")` down the other branch with no error.

## Cause

`PyAttrExists` asked the field table, the user METHOD table, the pylib method
alias, the str-method table and the int-method names — every kind of member
except a **property**. pylib's `Exception.args` is exactly that: a property over
a derived getter, deliberately (see its declaration note). `FindUProp` already
walks ancestors like `FindUMeth` does; it simply was not asked.

## The half that made it a two-part fix

Teaching `hasattr` alone was worse than the bug. `getattr(o, "p")` resolves a
literal name against declared FIELDS (`PyAttrFieldIdx`) and falls through to the
dynamic-attribute store, which knows nothing about properties — so it raised
`AttributeError` for a name `hasattr` had just answered True for, turning a
wrongly-taken branch into a crash. `PyMakePropRead` now builds the read `o.p`
builds (backing field, or the getter call), and the getattr path uses it.

## Known remaining gap, deliberately not fixed here

A **computed** name — `getattr(o, nm)` / `hasattr(o, nm)` where `nm` is a
variable — goes through the RUNTIME dynamic-attribute predicate, which is
RTTI-based and cannot see properties. Filed as
[[bug-nilpy-a-computed-attribute-name-cannot-see-a-property]]; the test asserts
the computed form only for a field and an absent name, and says why.

## Gate

`test/test_nilpy_hasattr_getattr_property.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: a property on a class and on a SUBCLASS, a plain
field, a method, an absent name, `getattr` with and without a default,
`e.args` on a constructed exception and on a caught one, and the computed-name
form for the shapes it supports. `test_nilpy_hasattr_builtin_receivers` and
`test_nilpy_getattr_dunder` re-run unchanged. `gate.sh quick` GREEN.
