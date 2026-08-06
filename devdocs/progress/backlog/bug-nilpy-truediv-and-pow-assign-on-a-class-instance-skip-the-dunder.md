---
prio: 50
---

# bug(N): `obj /= n` and `obj **= n` on a class instance skip the dunder and raise "expected a number, got object"

- **Track:** N (Nil-Python frontend). Files: `compiler/pyparser.inc`.
- **Found:** 2026-08-06, grepping the bug CLASS after fixing
  `regression-test-core-test-nilpy-augmented-assign-class-dunder`.
- **Pre-existing** — reproduces identically on `stable_linux_amd64/default/pinned`,
  so this is NOT a regression from e8450c58d67e.

## Repro

```python
class D:
    def __init__(self, v: int):
        self.v = v
    def __itruediv__(self, o):
        return D(self.v // o)
    def __ipow__(self, o):
        return D(self.v ** o)

d = D(10)
d /= 2
print(d.v)      # CPython: 5
e = D(3)
e **= 2
print(e.v)      # CPython: 9
```

CPython prints `5` then `9`. pxx compiles the program and then dies at run time:

```
Unhandled exception: TypeError: expected a number, got object
```

## Root cause (measured, not reasoned)

`PyCollectModuleLocalsAST` has two module-scope token-shape arms that assert a
*type* from a token pair alone:

- the `tkTrueDivEq` arm notes `tyDouble` for the target
- the `tkPowEq` arm notes `tyVariant`

Neither is an int/float-only operator — `/=` and `**=` dispatch `__itruediv__` /
`__ipow__` (then the binary form + rebind) exactly as `+=` dispatches `__iadd__`.
For a class-typed target the notes join through `PyWiden`:

- `PyWiden(tyClass, tyDouble)` falls to the closing "two kinds that both BOX"
  rule and yields `tyVariant`
- `PyWiden(tyClass, tyVariant)` yields `tyVariant` directly

So the name becomes a **variant holding an object**, and augmented-assign
dispatch on a variant does not find the dunder — it takes the numeric path and
hits the runtime `TypeError`. Same family as
`bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant`.

Why `+=` is already correct: its arm (the `tkPlusEq/tkMinusEq/tkStarEq/tkShlEq`
one) now notes `tyPromoInt64` **only when the target is already known to be an
integer**, deferring to a later fixpoint round otherwise — precisely so it
cannot assert a type it has not established. That guard is the shape the `/=`
and `**=` arms are missing.

## Fix sketch

Give both arms the same "already known to be numeric" guard the `+=` arm has:
look up `PyFindConstraint` (falling back to `PyProgSym`), and note the type only
when the target is a numeric/unknown-but-scalar kind — never over a `tyClass`.
Then the class-typed target keeps `tyClass` and reaches the dunder-dispatch path
that `+=` already takes correctly.

Note the *loud* failure mode here (a runtime `TypeError`, not a wrong value) is
why this stayed hidden rather than corrupting results — but a valid CPython
program not running is still an upward-compatibility break, so it is a bug and
not a divergence.

## Gate
`make compiler/pascal26` + the repro above diffing clean against CPython +
`tools/gate.sh quick`. Add the repro to `test/` with an inline Makefile
expectation, next to `test_nilpy_augmented_assign_class_dunder.npy`.
