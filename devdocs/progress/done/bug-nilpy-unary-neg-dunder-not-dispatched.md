---
track: N
prio: 40
type: bug
blocked-by: []
---

# `-n` on a user class silently computed garbage — `__neg__` never dispatched

Found immediately after landing the binary arithmetic dunder dispatch
(`bug-nilpy-arithmetic-operator-dunders-not-dispatched`) — the unary form has
the identical root cause.

```python
class Neg:
    def __init__(self, v):
        self.v = v
    def __neg__(self):
        return Neg(-self.v)
n = Neg(5)
print(-n)
```
CPython: `Neg(-5)` (repr, via `__repr__` not shown here but same idea). pxx
(before this fix): printed a huge garbage unsigned integer (the class
pointer negated as if it were an ordinary value).

## Fix

`compiler/parser.inc`'s `ParseFactorCore` unary-minus case (`tkMinus`)
unconditionally built a plain `AN_NEG` node over the operand with no dunder
check. Added a `PyExprMode`-gated check identical in shape to the binary
dunder fix: when the operand is a genuine user class, dispatch to its
`__neg__` via the existing `PyCallMeth1` helper instead of building `AN_NEG`;
no matching dunder is a clear compile error. Verified postfix chaining after
a negated class value still works (`(-n).get()`), and ordinary numeric unary
minus (including the `-7 // 2` precedence case a neighboring comment already
called out) is unaffected.

Regression test `test/test_nilpy_neg_dunder.npy` gated in `test-nilpy`. Full
suite + `--tier quick` green. Self-host confirmed byte-identical.

## Log
- 2026-07-31 — resolved, commit HEAD.
