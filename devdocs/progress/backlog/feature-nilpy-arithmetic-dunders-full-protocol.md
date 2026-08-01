---
track: N
prio: 40
type: feature
---

# Arithmetic dunders (`__add__`, `__sub__`, …) — full protocol

Phase 2 of [[feature-nilpy-arithmetic-ordering-dunders]] (umbrella), decided
in [[decide-nilpy-arithmetic-dunder-scope]]. Do after
[[bug-nilpy-comparison-dunders-not-dispatched]] lands.

```python
class C:
    def __init__(self, v):
        self.v = v
    def __add__(self, o):
        return self.v + o.v
print(C(1) + C(2))     # CPython: 3     pxx: 268329319137376 (adds the HANDLES)
```

Two `tyClass` operands on `+`/`-`/`*`/`/`/`//`/`%`/`**` take the raw
`IR_BINOP` path and operate on the instance pointers.

## Why this is bigger than phase 1

Unlike comparisons, arithmetic operators already have legitimate
special-cased class-operand routes (`Path("a") / "b"` is pathlib's join).
A blanket "any class operand checks the dunder first" rule has to be
threaded through every operator and compose with whatever else already
special-cases a class operand on that operator, per-operator, without
breaking the existing cases. `IRPyNumStrClash`'s str-vs-number clash check
also only fires for that one pair today — extending it to any class operand
isn't safe without the same per-operator care.

Land one operator at a time, `+`/`-` first (pathlib's actual collision) so
the composition question is answered where it's real, not guessed.

## Scope

`__add__`/`__radd__`, `__sub__`/`__rsub__`, `__mul__`, `__truediv__`,
`__floordiv__`, `__mod__`, `__pow__`, and their reflected forms as CPython
actually falls back to them. No matching dunder → genuine runtime
TypeError, not silent pointer arithmetic.

## Gate

`make test-nilpy` + self-host byte-identical, `.npy` per operator vs
CPython's own output, plus a regression confirming pathlib's `/` (and any
other existing special-cased class-operand route) is unaffected.
