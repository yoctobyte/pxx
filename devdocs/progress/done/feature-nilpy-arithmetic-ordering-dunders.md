---
track: N
prio: 60
type: feature
status: done
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

## 2026-08-09 — both phases complete; umbrella resolved

- **Phase 1**, [[bug-nilpy-comparison-dunders-not-dispatched]] — done
  (in `done/`).
- **Phase 2**, [[feature-nilpy-arithmetic-dunders-full-protocol]] — done today.
  Direct, reflected and in-place forms of `+ - * / // % **`, then `__divmod__`
  as its last named gap.

Re-measured at HEAD rather than taken on trust, since this ticket's own opening
paragraph (`C(1) + C(2)` adding instance pointers) is a PRE-WORK snapshot and
had been stale for a week: `+ - * / // % **` and `__radd__` all match CPython,
and the umbrella's Gate condition — no matching dunder gives a genuine runtime
TypeError rather than silent handle arithmetic — holds.

Explicitly NOT covered, tracked separately and deliberately left open:

- [[bug-nilpy-matmul-operator-does-not-parse]] — `@` has no infix token (p20).
- [[bug-nilpy-power-augmented-assign-does-not-parse]] — `**=`, same shape.
- [[decide-nilpy-runtime-dunder-dispatch-mechanism]] — operands reached as
  runtime variants through a container or parameter. Note that the `__eq__`,
  `__lt__`/`__gt__` and `__divmod__` work landed 2026-08-08/09 supplies a
  worked mechanism for exactly that (`PyUserObjBoolDunder` /
  `PyUserObjObjDunder` over the class RTTI), so that decision now has an
  implementation to point at rather than a blank page.
- [[bug-nilpy-static-typed-operands-skip-mixed-type-guard]] — mismatched static
  pairs computing instead of raising.

## Log
- 2026-08-09 — resolved, commit dc2e5b46f.
