---
track: N
prio: 60
type: bug
---

# Comparison dunders (`__lt__`/`__eq__`/`__gt__`/…) not dispatched — silent handle comparison

Phase 1 of [[feature-nilpy-arithmetic-ordering-dunders]] (umbrella), decided
in [[decide-nilpy-arithmetic-dunder-scope]].

```python
class C:
    def __init__(self, v):
        self.v = v
    def __lt__(self, o):
        return self.v < o.v
print(sorted([C(3), C(1), C(2)], key=lambda x: x))  # or: C(1) < C(2)
```

Two `tyClass` operands on `<`/`<=`/`>`/`>=` take the raw comparison path and
compare instance pointers — silent, no error, order depends on allocation
address not the user's `__lt__`. `__eq__` dispatch already works (see the
parent bug's measured table) — this is the rest of the comparison set.

## Why this phase first

No existing special-cased class-operand route on `<`/`>` today (unlike `/`
for pathlib on arithmetic operators), so dispatching to the dunder when
present cannot collide with anything already special-cased. Same shape as
the already-landed `__len__`/`__contains__`/`__call__`/`__getitem__`/
`__setitem__` fixes — use those as the template
(`bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic`, now
`done/`).

## Scope

`__lt__`, `__le__`, `__gt__`, `__ge__` (Python doesn't require all four —
CPython falls back to reflected/identity rules when only some are defined;
match CPython's actual behavior, verify against it rather than guessing).
No matching dunder → genuine runtime TypeError, not silent pointer
comparison.

## Gate

`make test-nilpy` + self-host byte-identical, `.npy` vs CPython's own
output (including a `sorted()`/`min()`/`max()` case, the main real use).
