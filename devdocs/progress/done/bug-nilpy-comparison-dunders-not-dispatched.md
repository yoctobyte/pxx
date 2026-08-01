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

## FIXED 2026-08-01 — operator path

### Measured first, both directions

The bug is real and was silent, as described. Against CPython, on the
self-hosted binary at `da085e9de`:

| expression | CPython | pxx before |
| --- | --- | --- |
| `C(3) < C(1)` | `False` | **`True`** (pointer compare — allocation order) |
| `C(1) < C(3)` | `True` | **`False`** |
| `sorted([C(3), C(1), C(2)])` | `[C(1), C(2), C(3)]` | `TypeError: expected a number, got object` |

Also corrected while here: the comment at `compiler/parser.inc:13833` claimed
"`__lt__` and `__len__` already dispatched". `__lt__` appeared **nowhere** in
`compiler/**` — only `__len__` was true. The comment was wrong, not the ticket.

### CPython's rule, measured rather than assumed

Ordering does NOT mirror `==`. Verified directly:

- `a < b` tries `a.__lt__(b)`, else the REFLECTED `b.__gt__(a)`; `>` ↔ `__gt__`
  /reflected `__lt__`; `<=` ↔ `__le__`/`__ge__`; `>=` ↔ `__ge__`/`__le__`.
  A class defining **only** `__lt__` therefore supports both `<` and `>` — that
  fallback is the half a naive implementation drops.
- No dunder at all → **TypeError**. There is no identity fallback the way `==`
  has one (`Bare(1) == Bare(1)` is `False`, but `Bare(1) < Bare(2)` raises).

### The fix

- `compiler/parser.inc` — ordering dispatch in `ParseExpr` beside the existing
  `__eq__` block: direct dunder on the left operand, else the reflected partner
  on the right, else a runtime raise. Built via `PyCallMeth1` at AST level, not
  hand-rolled IR, for the reason the `__eq__` block records (the `other`
  parameter is an unannotated by-reference variant; a hand-built `IR_ARG` skips
  `IRLowerCallArg` — `project_irlowercallarg_hand_built_args_landmine`).
- `compiler/builtin/pylib.pas` — `PyNotOrderableError`, sibling of
  `PyNotContainerError`/`PyNotCallableError`. A genuine RUNTIME raise, so a
  `try/except` around a comparison still compiles and runs its handler.
- `test/test_nilpy_dunder_ordering.npy` + `make test-nilpy` wiring. Covers all
  four operators, the reflected-only-`__lt__` case, the raise, and that `==`
  keeps its identity fallback. Output is **byte-identical to CPython's**.

### Scope NOT covered — split out, not left implicit

`sorted()`/`min()`/`max()` still raise, and `print([obj])` still prints `[, ]`.
That is a **different mechanism**, not a leftover of this one: those reach the
instance through a container, where the element is a `Variant` and the class is
known only at RUN time, so no compile-time dispatch can fire. There is no
runtime dunder dispatch in pylib at all (confirmed by reading `pyvar_gt` and by
measuring `__repr__`, which prints empty rather than raising).

Filed as [[bug-nilpy-dunders-not-dispatched-through-containers]], blocked on
[[decide-nilpy-runtime-dunder-dispatch-mechanism]] (Track U) — the mechanism is
a real fork (runtime RTTI lookup vs. dunder slot table vs. monomorphisation)
and guessing it here would have been the wrong call.

So this ticket closes the **operator** half only; the ticket's own gate line
asking for a `sorted()` case moves to the split-out ticket with it.

### Regression caught by the gate — pylib's containers are `tyClass` too

The first version of the fix guarded only on "both operands are `tyClass` with a
resolvable class row". That is **not** the same as "genuine user object":
`TPyList`/`TPyDict`/`TPyBytes` satisfy it as well. So `[1, 2] < [1, 3]` — which
already compared LEXICOGRAPHICALLY further down — was captured by the new branch,
found no `__lt__` on `TPyList`, and raised `PyNotOrderableError`. Working list
comparison became a runtime abort.

`make test-nilpy` caught it on `test_nilpy_mixed_type_operands`; it was never
pushed. Worth recording because the trap is generic to **every** dunder-dispatch
branch in this frontend, not to ordering: the `__contains__` dispatch already
carries the same exclusion, and any future `__add__`-style branch needs it too.

Fixed with `PyRecIsPylibOwnClass` (`compiler/symtab.inc`), keyed on the
**declaring unit** (`UClsUnitIdx` = `pylib`) rather than on a list of class
names. The existing `__contains__` guard hard-codes `TPyList`/`TPyDict`/
`TPyBytes`, which is exactly the kind of list that rots as pylib grows another
container; the unit check covers all of them by construction and cannot drift.

Re-verified after the fix: `test_nilpy_mixed_type_operands` matches its expected
output exactly, and `test_nilpy_dunder_ordering` still matches CPython.

## Log
- 2026-08-01 — resolved, commit HEAD.
