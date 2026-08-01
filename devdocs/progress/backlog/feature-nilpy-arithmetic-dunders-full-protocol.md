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

## 2026-08-01 — measured against CPython, whole scope quantified

Differential sweep (1094 cases, self-hosted binary at `3f2c5b915`). Every row
below is measured, not inferred. `C` is a plain user class; `v` is `7`/`3`.

### Dunder declared but NOT dispatched

| expression | CPython | pxx |
| --- | --- | --- |
| `C(7) // C(3)` (`__floordiv__`) | `2` | **`0`** |
| `C(7) % C(3)` (`__mod__`) | `1` | **`126959237464088`** |
| `C(7) ** C(3)` (`__pow__`) | `343` | `TypeError` |

`__floordiv__`, `__mod__`, `__pow__` appear **nowhere** in `compiler/**`.

### Dunder MISSING — must raise, instead computes on the handle

| expression | CPython | pxx |
| --- | --- | --- |
| `C(7) // C(3)` | `TypeError` | **`0`** |
| `C(7) % C(3)` | `TypeError` | **`138903256301592`** |
| `C(7) + C(3)` | `TypeError` | *compile error* — see below |

### Reflected forms — none work

`3 <op> C(4)` where `C` declares only `__radd__`/`__rsub__`/`__rmul__`/
`__rtruediv__`/`__rfloordiv__`/`__rmod__`/`__rpow__`: **all seven diverge.**
Measured: `3 + C(4)` → `1744830491` (CPython `radd`), `3 * C(4)` →
`-1906311096` (CPython `rmul`). Note `__radd__`/`__rmul__`/`__rsub__`/
`__rtruediv__` *do* appear as strings in `compiler/**`, so the names are known
but the dispatch does not fire — worth finding out why before writing new code,
since a partially-wired path is a different fix from an absent one.

### Already filed separately, do not re-file

- Missing `__add__`/`__sub__`/`__mul__`/`__truediv__`/`__neg__` aborts
  COMPILATION instead of raising →
  [[bug-nilpy-missing-arith-dunder-aborts-compile-instead-of-raising]].
- Bitwise/shift operators **segfault** →
  [[bug-nilpy-bitwise-shift-on-class-operand-segfaults]].
- `__abs__`/`__invert__`/`__index__` return the raw handle →
  [[bug-nilpy-unary-numeric-dunders-return-raw-handle]].

### Sequencing note

The landed ordering-dunder fix
([[bug-nilpy-comparison-dunders-not-dispatched]]) is the working template,
**including the trap it hit**: guarding on "operand is `tyClass`" also captures
pylib's own `TPyList`/`TPyDict` and broke `[1,2] < [1,3]`. Use
`PyRecIsPylibOwnClass` (`compiler/symtab.inc`), not a class-name list. That trap
is more dangerous here than for ordering, because pylib's containers have real
`+` (concat) and `*` (repeat) semantics that a naive guard would capture.

## 2026-08-01 — __floordiv__ / __mod__ / __pow__ LANDED

The three measured-broken direct forms are done. All verified against CPython:

| expression | was | now |
| --- | --- | --- |
| `C(7) // C(3)` | `0` | `2` |
| `C(7) % C(3)` | `126959237464088` | `1` |
| `C(7) ** C(3)` | `TypeError` | `343` |

- `//` and `%` joined the existing `*` / `/` dunder branch in `ParseTerm`
  (`compiler/parser.inc`) — `ParseTerm` already loops on `tkDiv`/`tkMod`, so it
  was a widened condition plus two method names.
- `**` is dispatched in the power arm of `ParseFactor`, ahead of the `pypow_v`
  call the base was previously boxed into.
- All three now carry the `PyRecIsPylibOwnClass` exclusion, and it was added to
  the pre-existing `*` / `/` branch in the same change — that branch had none,
  and it matters more for `%` than for `*` because pylib's rows have real
  semantics on these operators.

`test/test_nilpy_dunder_arith2.npy` is byte-identical to CPython: numeric
results, a class returning NON-numeric tags (which proves the method ran rather
than a numeric path coincidentally agreeing), plain `// % **` including the
negative-operand rules, and `"%d apples" % 5` staying string FORMATTING rather
than being captured as `__mod__`.

Native confirm: self-host fixedpoint A==B==C from the pinned seed, testmgr
--tier quick GREEN; matrix offloaded to Track T.

### Deliberately not asserted in that test

`[1, 2] // [3]` should raise `TypeError` and still returns `0`. That is
[[bug-nilpy-static-typed-operands-skip-mixed-type-guard]], a different bug with
a different fix; encoding today's answer either way would freeze it, so the test
says so in a comment instead.

### What remains on this ticket

**The reflected forms — all seven still broken** (`__radd__`, `__rsub__`,
`__rmul__`, `__rtruediv__`, `__rfloordiv__`, `__rmod__`, `__rpow__`). Measured:
`3 + C(4)` → `1744830491`, `3 * C(4)` → `-1906311096`. Note four of those names
already appear in `compiler/**`, so check what the existing references do before
writing new code — a partially-wired path is a different fix from an absent one.

## 2026-08-01 — REFLECTED forms LANDED; this ticket's scope is now complete

All seven, verified against CPython:

| expression | was | now |
| --- | --- | --- |
| `3 + C(4)` | `1744830491` | `radd:3` |
| `3 - C(4)` | (handle math) | `rsub:3` |
| `3 * C(4)` | `-1906311096` | `rmul:3` |
| `3 / C(4)` | `0.000000000022` | `rtruediv:3` |
| `3 // C(4)` | `0` | `rfloordiv:3` |
| `3 % C(4)` | `3` | `rmod:3` |
| `3 ** C(4)` | `TypeError` | `rpow:3` |

**The "partially wired" worry is resolved: they were simply absent.** Four
reflected names did appear in `compiler/**`, which earlier notes flagged as a
reason for caution — grepping showed all of them are in COMMENTS saying the
fallback "is not implemented". No half-built path existed.

`PyReflName` (operator → reflected method name) plus `PyReflectedDunder`
(`compiler/parser.inc`) — one table and one dispatcher, so the three call sites
(`ParseSimpleExpr` for `+`/`-`, `ParseTerm` for `*` `/` `//` `%`, the power arm
of `ParseFactor` for `**`) cannot drift apart. Each reflected check is gated on
the LEFT operand NOT being a user class, so left-operand priority is preserved
by construction rather than by ordering luck.

`test/test_nilpy_dunder_reflected.npy` is byte-identical to CPython and covers
the precedence rule explicitly: a class declaring BOTH `__add__` and `__radd__`
must answer `direct` when it is on the left and `reflected` when on the right.
That case exists because getting the receiver/argument swap backwards produces a
plausible wrong answer rather than an error. Also asserts that plain arithmetic,
string concat/repeat and list concat are untouched.

Native confirm: self-host fixedpoint A==B==C from the pinned seed, testmgr
--tier quick GREEN; matrix offloaded to Track T.

### Ticket status

Direct and reflected forms for `+ - * / // % **` are all done. What is NOT here,
and is tracked elsewhere:

- missing dunder aborts COMPILATION instead of raising →
  [[bug-nilpy-missing-arith-dunder-aborts-compile-instead-of-raising]]
- operands reached through a container/parameter (runtime variant) →
  [[decide-nilpy-runtime-dunder-dispatch-mechanism]]
- mismatched static operand pairs computing instead of raising →
  [[bug-nilpy-static-typed-operands-skip-mixed-type-guard]]
