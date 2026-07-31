---
track: N
prio: 55
type: bug
blocked-by: []
---

# `Vector(1,2) + Vector(3,4)` silently computed garbage — arithmetic dunders never dispatched

Found by proactive CPython-diff sweeping — another silent-wrong-value bug
(this repo's known worst failure mode).

```python
class Vector:
    def __init__(self, x, y):
        self.x = x; self.y = y
    def __add__(self, other):
        return Vector(self.x + other.x, self.y + other.y)
a = Vector(1, 2)
b = Vector(3, 4)
print(a + b)
```
CPython: `(4, 6)`. pxx (before this fix): compiled cleanly, printed a garbage
integer (the raw pointer/handle arithmetic on the two class instances).
`__mul__`/`__truediv__` had the identical problem for `*`/`/`.

## Root cause

Nowhere in `compiler/parser.inc`'s shared binop-typing chain was a user
class's `+`/`-`/`*`/`/` ever checked against its own `__add__`/`__sub__`/
`__mul__`/`__truediv__` methods — only Pascal's own `operator +` overload
registry (`FindOpOverload`, populated by the distinct `operator +(a, b: T):
T;` Pascal syntax) was consulted, and NilPy's Python-style dunder methods
(found via `FindUMeth`, the same mechanism `__repr__`/`__eq__`/`__len__`
already use) were never wired to the arithmetic operators at all. A tyClass
operand simply fell through to the generic numeric/pointer typing, which
computed on the class HANDLE as if it were an ordinary integer.

## Fix

Added a `PyExprMode`-gated dispatch branch in both `ParseSimpleExpr` (`+`/`-`)
and `ParseTerm` (`*`/`/`), placed after the existing list/dict/bytes
container-specific branches (so those keep priority) and guarded on the LEFT
operand being a genuine tyClass with a resolvable user-class record id: build
`left.__add__(right)` (etc.) via the existing `PyCallMeth1` helper (the same
one method-call desugaring elsewhere in this frontend already uses). If the
class has no matching dunder, raises a clear compile error instead of
falling through to garbage arithmetic. Only the LEFT operand's class is
consulted (Python's own left-operand-first dunder lookup) — no
`__radd__`/`__rmul__`/etc. right-operand fallback (so `3 * Vector(...)`,
reflected-operator order, is not yet supported).

Regression tests: `test/test_nilpy_operator_dunders.npy` (all four operators,
diffed against CPython) and `test/test_nilpy_operator_dunder_missing_fail.npy`
(the established `_fail.npy` convention — a class with no dunder now errors
clearly instead of silently corrupting). Both gated in `test-nilpy`. Full
`test-nilpy` suite + `--tier quick` green (confirms no existing list/set/
string/dict operator path was disturbed by this broader change). Self-host
confirmed byte-identical via `make pxx-debug`.

## Log
- 2026-07-31 — resolved, commit HEAD.
