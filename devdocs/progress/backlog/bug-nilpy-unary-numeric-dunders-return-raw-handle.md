---
summary: "NilPy: abs(obj), ~obj and obj-as-index ignore __abs__/__invert__/__index__ — they return the raw instance HANDLE as a number, silently"
type: bug
track: N
prio: 55
---

# `__abs__`/`__invert__`/`__index__` never dispatched — raw handle used as the value

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases).

## Measured (self-hosted binary at `3f2c5b915`)

```python
class C:
    def __init__(self, v): self.v = v
    def __abs__(self): return abs(self.v)
print(abs(C(-5)))
```
CPython: `5`. pxx: **`140450157559832`** — the instance pointer.

```python
class C:
    def __invert__(self): return "INVERTED"
print(~C())
```
CPython: `INVERTED`. pxx: **`123900459483161`.**

```python
class C:
    def __index__(self): return 2
print([10, 20, 30][C()])
```
CPython: `30`. pxx: **`IndexError: list index out of range`** — the handle was
used as the subscript.

## Cause

`__abs__`, `__invert__` and `__index__` appear **nowhere** in `compiler/**`
(`grep -oh '__[a-z_]*__' compiler/*.inc`), so nothing dispatches them and each
operand falls through to the numeric path with the instance handle standing in
for the value.

Note `__neg__` **is** dispatched (`compiler/parser.inc:8901`) — so unary minus
already has the branch these three need, and it is the natural place to model
the fix on. (That site raises a compile-time `Error()` when the dunder is
missing, which is its own defect —
[[bug-nilpy-missing-arith-dunder-aborts-compile-instead-of-raising]].)

## Severity split

`__abs__` and `__invert__` are the silent ones: a plausible large integer, no
error, wrong wherever it flows. `__index__` at least raises here, but only by
luck — the handle happened to exceed the list length; for a short-lived small
handle it would silently index the wrong element.

## Fix shape

Mirror the landed ordering-dunder dispatch: dispatch when declared; when not
declared raise a genuine runtime `TypeError` via a pylib helper rather than
falling through to handle arithmetic. Apply the `PyRecIsPylibOwnClass` guard
(`compiler/symtab.inc`) so pylib's own rows keep their behaviour.

`__index__` additionally needs wiring at every integer-coercion site, not just
subscripts (slice bounds, `range()`, repeat counts) — worth scoping when picked
up, and a reason not to fold it silently into an `__abs__` fix.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython for each dunder declared and not declared (must raise a catchable
`TypeError`, never a handle-valued number).

## PARTIALLY FIXED 2026-08-01 — __abs__ and __invert__ done, __index__ remains

- `__invert__`: `PyParseBitOperand`'s `~` arm (`compiler/pyparser.inc`) now goes
  through `PyBitDunder`, the same helper the binary bitwise operators use — so
  it inherits the pylib exclusion and the runtime-`TypeError`-when-absent
  behaviour for free.
- `__abs__`: the `Abs`/`Sqr` builtin arm (`compiler/parser.inc`), dispatched
  ahead of the existing variant (`pyabs_v`) and numeric helper paths so those
  are untouched.

Both verified against CPython: `abs(Num(-5))` → `5` (was `140450157559832`),
`~Num()` → the method's result (was `123900459483161`).
`test/test_nilpy_dunder_unary.npy` is byte-identical to CPython and also covers
the no-dunder `~` raising a catchable TypeError, plus plain numeric `abs`/`~`
being unaffected.

Native confirm: self-host fixedpoint A==B==C from the pinned seed, testmgr
--tier quick GREEN; matrix offloaded to Track T.

### Still open: `__index__`

Deliberately not attempted here. As the ticket's own scope note says, it needs
wiring at every integer-coercion site (subscripts, slice bounds, `range()`,
repeat counts), not just the one subscript case the sweep measured — that is a
different, wider change and folding it in silently would have left most sites
wrong. Ticket stays open for it.
