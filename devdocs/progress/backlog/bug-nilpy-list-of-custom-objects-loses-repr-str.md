---
track: N
prio: 40
type: bug
blocked-by: []
---

# A user class instance boxed in a list/dict prints as empty, losing `__repr__`/`__str__`

Found by proactive CPython-diff sweeping. `print(p1)` on a bare, statically
class-typed local correctly calls `__repr__`/`__str__` (the compiler knows
`p1`'s class at compile time and emits a direct method call). But once the
SAME instance is boxed into a `TPyList`/`TPyDict` (as a `Variant` element, its
static class identity erased), printing the container renders each element as
an EMPTY string instead of calling the class's `__repr__`:

```python
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y
    def __repr__(self):
        return f"Point({self.x}, {self.y})"
p1 = Point(1, 2)
p2 = Point(1, 2)
print(p1)          # Point(1, 2) -- correct
print([p1, p2])    # CPython: [Point(1, 2), Point(1, 2)]   pxx: [, ]
```

## Root cause

`pyvar_repr`/`pystr_of` (`compiler/builtin/pylib.pas`) dispatch on the
Variant's runtime tag: tag 7 (VT_OBJECT) is special-cased for `TPyList`/
`TPyDict`/`TPyBytes` only (`if o is TPyList then ... if o is TPyDict then ...`)
and everything else falls through to `pyrepr_of`/`VariantToStr`, which has no
concept of a user-defined class or its `__repr__`/`__str__` method — pylib.pas
is a plain runtime unit compiled once, with no visibility into classes a NilPy
program declares later.

This is the SAME underlying architectural gap as the already-open
`feature-nilpy-runtime-method-dispatch-on-variant` (confirmed still open,
2026-07-31 recon): a class instance that reaches pylib's runtime helpers only
as a bare Variant handle has no way to call back into its own class's methods
without new runtime type-dispatch machinery (test the receiver's class tag,
branch to its own `__repr__`/`__str__` VMT slot, fall back to the default
`ClassName(...)` object repr CPython itself uses when neither dunder is
defined). Filed separately since the container-print path is a distinct
manifestation from that ticket's method-name-ambiguity case, but any fix
belongs to the same runtime-dispatch effort.

Not attempted here — same class of problem the sibling ticket already scoped
as "new runtime type-dispatch codegen, not a quick patch."
