---
track: N
prio: 60
type: feature
---

# NilPy arithmetic/ordering dunders — umbrella

Python's operator overloading (`__add__`, `__lt__`, …) is the same feature
as Pascal's `operator +` overload syntax, already supported for Pascal. This
is the NilPy side of it. Split out of
[[bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic]] via
[[decide-nilpy-arithmetic-dunder-scope]] (DECIDED 2026-08-01: phased, low
risk first).

Today `C(1) + C(2)` on two `tyClass` operands takes the raw `IR_BINOP` path
and adds the instance pointers — silent, no error, a different plausible
number every run.

## Phasing (the decision)

1. **[[bug-nilpy-comparison-dunders-not-dispatched]]** — `__lt__`/`__eq__`/
   `__gt__`/etc. No existing special-cased class-operand route on `<`/`>`
   today, so no collision risk. Covers the most likely real use
   (`sorted()`/`min()`/`max()` on custom-ordered objects). Do this first.
2. **[[feature-nilpy-arithmetic-dunders-full-protocol]]** — `__add__` etc.
   Bigger: has to compose per-operator with existing special-cased
   class-operand routes (e.g. `Path("a") / "b"` for pathlib) without
   breaking any of them. Do after (1), one operator at a time.

## Gate

`make test-nilpy` + self-host byte-identical, `.npy` per dunder vs CPython's
own output. No matching dunder → genuine runtime TypeError (matching
`PyNotContainerError`/`PyNotCallableError`/`PyNoSetitemError`), never a
silent handle-arithmetic result.
