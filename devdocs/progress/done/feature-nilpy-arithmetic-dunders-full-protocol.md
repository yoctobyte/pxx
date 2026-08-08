---
track: N
prio: 40
type: feature
status: done
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

## 2026-08-03 — re-measured; the subject of this ticket ALREADY WORKS

Run against HEAD rather than re-read. The ticket's own reproducer
(`print(C(1) + C(2))` with `__add__` declared) now prints `3`, not a sum of
handles. Full operator matrix, all diffed against CPython and all correct:

| form | result |
| --- | --- |
| `a + b`, `a - b`, `a * b`, `a / b`, `a // b`, `a % b`, `a ** b` on two instances | all correct |
| mixed type — `c + 3` via `__add__` | correct |
| reflected — `3 + c` via `__radd__` | correct |
| **augmented — `d += 5`** | **0, silently** |

So this feature landed at some point without the ticket being updated — the
"adds the HANDLES" symptom in the header is stale, and the phase-2 framing
(threading a blanket rule through every operator, composing with `Path("a") /
"b"`) describes work that has evidently been done.

**The one remaining hole is split out as
[[bug-nilpy-augmented-assign-on-a-class-instance-silently-yields-zero]]** — a
silent wrong answer (`0`, no diagnostic), which also reproduces with only
`__add__` declared, i.e. it is the augmented-assignment path rather than
`__iadd__` specifically. Filed separately because a silent wrong answer buried
as one line in a 195-line feature ticket stays invisible.

**Do not close this ticket on the strength of the table above** — what was
measured is the operator dispatch, not this ticket's full phase-2 scope
(in-place operators beyond `+=`, `__divmod__`/`__matmul__`-shaped members, and
the composition-with-existing-special-cases concerns below were not swept).
Re-scope it against what remains rather than re-deriving the parts that work.

## 2026-08-03 (later) — in-place operators re-scoped by measurement

The 2026-08-03 note above left "in-place operators beyond `+=`" as unswept
remaining scope. Swept now, against CPython, on three target shapes — a bare
name, a class-typed field, and an in-method `self.` target:

`-= *= /= //= %= &= |= ^= <<= >>=` all dispatch the in-place dunder, fall back
to the binary one with a rebind, and raise a catchable TypeError with neither.
So this line of the remaining scope is **closed**, pinned by
`test/test_nilpy_augmented_assign_class_dunder.npy` (name target) and
`test/test_nilpy_augmented_assign_class_field.npy` (field target, added with
[[bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero]]).

**One exception, split out:** `**=` is a hard parse error —
[[bug-nilpy-power-augmented-assign-does-not-parse]]. It is not a gap in this
protocol so much as a consequence of power being the one operator with no
token: `**` is two `tkStar` plus an ad-hoc lookahead, so there is no binary
token for `PyAugDunderName` to key `__ipow__` off. Filed separately because the
fix is a new `TTokenKind` in `defs.inc` — Track A ground — rather than more
dunder plumbing.

Still genuinely open here, and still not swept: `__divmod__` / `__matmul__`-
shaped members, and the composition-with-existing-special-cases concerns above.

## 2026-08-09 — last named scope swept; __divmod__ LANDED, __matmul__ split out

The two items left as "still genuinely open and not swept" above are now
measured, and the ticket's scope is complete.

### `__divmod__` — was a CRASH, now matches CPython

`divmod(M(7), M(3))` reached `pyfloordiv_v` with two object handles and died
with **`Runtime error 219`** (a bad cast). It neither called `__divmod__` nor
raised — the worst of both.

`pydivmod_v` now dispatches `__divmod__`, then the reflected `__rdivmod__`, and
raises a catchable `TypeError` when a class declares neither (CPython's answer,
and what the crash was standing in for). All four arms verified against CPython:

| expression | was | now |
| --- | --- | --- |
| `divmod(D(7), D(3))` (`__divmod__`) | `Runtime error 219` | `(2, 1)` |
| `divmod(Bare(7), R(3))` (`__rdivmod__`) | `Runtime error 219` | `('rdivmod', 7, 3)` |
| `divmod(Bare(7), Bare(3))` (neither) | `Runtime error 219` | `TypeError` |
| `divmod(7, 3)` / `(-7, 3)` / `(7.5, 2)` | correct | unchanged |

Only an object-vs-object pair takes the new path; a mixed pair falls through to
the numeric one, which is why the numeric control is in the test. The result
must come back a `TPyList` (Python's contract is "a pair") — any other class is
left to the fallback rather than cast to a tuple it is not.

Mechanically it reuses the runtime dunder dispatch added the same night for
`__eq__`/`__lt__`, via a new object-RETURNING sibling of
`PyUserObjBoolDunder`. Pinned by `test/test_nilpy_divmod_dunder.{npy,expected}`
(`.expected` from CPython), wired into `test-nilpy`.

### `__matmul__` — split out, NOT done

`M(2) @ M(5)` is a parse error: `@` is only a decorator prefix today, never a
binary operator. Filed as [[bug-nilpy-matmul-operator-does-not-parse]] at prio
20, because it is the same shape as
[[bug-nilpy-power-augmented-assign-does-not-parse]] — an operator with no usable
token, so the fix is a `TTokenKind` in Track A's shared `defs.inc` and a
decorator-vs-infix disambiguation, not more dunder plumbing.

### The composition concern is answered

The ticket's standing worry was that a class-operand dunder rule would capture
`Path("a") / "b"`. Measured at HEAD: `Path("a") / "b"` still gives `a/b`, and
scalar/string/list `+ - * /` are unaffected (asserted in the sibling tests).

### Closing

Direct, reflected and in-place forms of `+ - * / // % **` were already done
(2026-08-01/03 notes above); `__divmod__` is done here; `__matmul__` and `**=`
are separately filed. Resolved. Verification for this pass: `tools/gate.sh
quick` GREEN, plus `ar1`/`dm3`/pathlib/`eq`/`lt` probes re-diffed against
CPython.

## Log
- 2026-08-09 — resolved, commit dc2e5b46f.
