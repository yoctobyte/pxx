---
track: N
prio: 70
type: bug
---

# `__eq__` is ignored — `==` on user objects compares identity

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __eq__(self, o) -> bool:
        return self.v == o.v

print(V(1) == V(1))   # CPython: True    pxx: False
print(V(1) != V(1))   # CPython: False   pxx: True
```

`==` falls through to a pointer comparison and never calls the user's
`__eq__`. `!=` is wrong in the same way, from the same cause.

Silent, and the failure direction is the bad one: two equal values report
unequal, so a membership test, a dedup or an `if got == expected` quietly takes
the wrong branch instead of failing loudly.

`__lt__` and `__len__` DO dispatch (`a < b` and `len(a)` are both correct), so
the operator-to-dunder machinery exists and `__eq__`/`__ne__` are simply not
wired into it.

Related but distinct: dict value equality is also identity-based
([[bug-nilpy-dict-equality-compares-identity]]). Together they mean `==` is
untrustworthy for every compound value that is not a list.

Found by the OOP sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus `==`/`!=` on a class with
`__eq__`, one without, across an inheritance pair, and against None.

## RESOLVED — dispatch `__eq__` at the comparison site

An arm in parser.inc's `==`/`!=` handling: when both operands are tyClass and
the LEFT operand's class (or an ancestor) declares `__eq__`, the comparison
becomes a call to it, with `!=` wrapping the result in AN_NOT. Same shape as
PyStrOfValue dispatching `__str__`, and non-virtual in the same way — it
resolves against the operand's static class.

Built at AST level through `PyCallMeth1`, deliberately NOT as hand-rolled IR:
the `other` parameter is normally unannotated, i.e. a by-reference variant, and
a hand-built IR_ARG skips IRLowerCallArg
([[project_irlowercallarg_hand_built_args_landmine]]). The result keeps the
METHOD's own return type rather than being forced to Boolean — the callee's ABI
decides.

Verified against CPython: equal and unequal instances, `!=`, self-comparison, a
subclass OVERRIDING `__eq__` (both directions), and a class with no `__eq__`
still comparing by identity.

## Two remainders, deliberately not in this change

- **`x in [list of objects]`** still compares by identity: `V(1) in [V(1)]` is
  False where CPython says True. That path is pylib's `PyVarEq` at RUN time,
  which cannot call back into a user method without a dispatcher — the same
  machinery `pyvar_callv*` provides for callable values. Filed as
  [[bug-nilpy-in-over-objects-ignores-eq]].
- **`obj == None` where `__eq__` dereferences its argument.** CPython calls
  `__eq__(obj, None)` and raises AttributeError; pxx answers False without
  calling it, because None is not tyClass so the arm does not fire. That is the
  behaviour a well-written `__eq__` (isinstance guard, NotImplemented) produces
  anyway, so it is recorded rather than chased.

### Gate

`tools/gate.sh full`.
