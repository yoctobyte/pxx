---
track: N
prio: 35
type: bug
blocked-by: []
---

# `list.sort()` on user objects with `__lt__` raises a runtime TypeError instead of using it

Found by proactive CPython-diff sweeping, right after fixing comparison-
adjacent arithmetic dunders (`bug-nilpy-arithmetic-operator-dunders-not-
dispatched`, `bug-nilpy-unary-neg-dunder-not-dispatched`) — this is the same
family of gap for the COMPARISON dunders specifically, surfaced through
`sort()`'s element comparisons.

```python
class Point:
    def __init__(self, x, y):
        self.x = x; self.y = y
    def __lt__(self, other):
        return (self.x, self.y) < (other.x, other.y)
pts = [Point(2,1), Point(1,2), Point(1,1)]
pts.sort()
```
CPython sorts using `__lt__`: `[(1,1), (1,2), (2,1)]`. pxx: runtime
exception —
```
Unhandled exception: TypeError: expected a number, got object
```
— `list.sort()`'s internal comparison assumes a numeric/string element and
never consults a class's `__lt__` (or `__eq__`/`__gt__`/etc.) at all.

## Scope note

**Confirmed separately**: a bare `<`/`==` EXPRESSION between two statically
class-typed operands (`Point(1,1) < Point(1,2)`, `a == b`) already dispatches
correctly to `__lt__`/`__eq__` — that parse-time comparison path is fine. So
this gap is ISOLATED to `.sort()`'s own internal element comparison, which
must go through a different, purely-runtime Variant-comparison helper
(operating on two boxed Variants with no static class context, likely near
`pyvar_lt`/`PyVarLess` in `compiler/builtin/pylib.pas`) that never got
taught to check for and call a class's own comparison dunder. The fix
therefore needs a RUNTIME class-tag check + dynamic method dispatch — the
same shape as the already-open `feature-nilpy-runtime-method-dispatch-on-
variant` — not a parse-time change like the arithmetic dunder fixes used.

Not attempted this pass — needs its own investigation into exactly which
runtime comparison helper `.sort()`'s internals call, and how to invoke a
class's method generically from that context (pylib.pas has no visibility
into user-defined classes compiled later, the same constraint noted in
`bug-nilpy-list-of-custom-objects-loses-repr-str`).

## Gate

A `.npy` case sorting a list of user objects with `__lt__`, diffed against
CPython, gated in `test-nilpy` + `--tier quick` + self-host byte-identical.
