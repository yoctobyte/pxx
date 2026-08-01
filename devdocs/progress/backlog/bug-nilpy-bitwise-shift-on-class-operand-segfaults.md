---
summary: "NilPy: `obj & 1` / `obj << 1` on a class instance SEGFAULTS (core dump); __and__/__or__/__xor__/__lshift__/__rshift__ are never dispatched"
type: bug
track: N
prio: 60
---

# Bitwise/shift operators on a class instance segfault

- **Type:** bug (NilPy, CRASH) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases).

## Measured (self-hosted binary at `3f2c5b915`)

```python
class C:
    def __and__(self, o): return "AND"
    def __or__(self, o):  return "OR"
    def __xor__(self, o): return "XOR"
c = C()
print(c & 1)
print(c | 1)
print(c ^ 1)
```
CPython: `AND` / `OR` / `XOR`.
pxx: **exit 139, core dumped.**

Identical for shifts:

```python
class C:
    def __lshift__(self, o): return "LSHIFT"
    def __rshift__(self, o): return "RSHIFT"
print(C() << 1); print(C() >> 1)
```
CPython: `LSHIFT` / `RSHIFT`. pxx: **exit 139, core dumped.**

## Cause

`__and__`, `__or__`, `__xor__`, `__lshift__`, `__rshift__` appear **nowhere** in
`compiler/**` (`grep -oh '__[a-z_]*__' compiler/*.inc`), so a class operand on
these operators is never dispatched and falls through to the integer bitwise
lowering with the instance HANDLE as the operand.

Unlike the arithmetic cases in this family (which silently compute a garbage
number — see [[feature-nilpy-arithmetic-dunders-full-protocol]]), this one
**crashes**, so something downstream dereferences rather than just computing on
the handle. Worth finding out what: a segfault from an ordinary binary operator
on a well-formed program is a bigger deal than the missing dispatch itself, and
it may be the same root as other handle-as-integer paths.

## Priority note

Ranked above the rest of the arithmetic-dunder work despite being rarer syntax:
it is the only member of the family that **crashes**, and a crash with no
diagnostic is worse than a wrong number for a user trying to find it.

## Fix shape

Same shape as the landed ordering-dunder dispatch: dispatch to the dunder when
the class declares it, and raise a genuine runtime `TypeError` (a
`PyNotOrderableError`-style pylib helper) when it does not — never fall through
to handle arithmetic. Apply the `PyRecIsPylibOwnClass` exclusion
(`compiler/symtab.inc`) so pylib's own containers keep their semantics; note
`TPyList`/set-like types may want real `|`/`&` set operations later, which is a
reason to route through the guard rather than around it.

Investigate the segfault separately even after dispatch lands — a class with
**no** such dunder must raise, and today that path is what crashes.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython for each of the five operators declared, and each one **not** declared
(must raise a catchable `TypeError`, not crash).

## FIXED 2026-08-01

### Why it crashed rather than computing garbage

Measured with `PXXDBG=a.ir:<proc>`: `x & 1` on a class operand produced
`binop ... tk=22` — the result typed **tyVariant**, because
`PyWiden(tyClass, tyInteger)` widens to a variant. The class HANDLE was then
stored through the variant path (`var_store`), which dereferences it as a
variant record. That is the segfault. The arithmetic operators merely compute on
the handle, which is why they return a wrong number where these die.

So the crash was a *consequence* of the missing dispatch, not a separate defect
— the ticket's "investigate the segfault separately even after dispatch lands"
note is answered: with dispatch (or a raise) in front, the variant-typed binop
is never built.

### The fix

`PyBitDunder` (`compiler/pyparser.inc`), called from all five operators —
`PyParseShift` (`<<`/`>>`), `PyParseBitAnd`, `PyParseBitXor`, `PyParseBitOr`.
Dispatches `__and__`/`__or__`/`__xor__`/`__lshift__`/`__rshift__` when declared;
otherwise raises `PyNotBitOperandError`, a new pylib helper — a genuine runtime
TypeError, so `try/except` around the expression still compiles and runs.

Carries the `PyRecIsPylibOwnClass` exclusion, and the callers' existing
set/dict arms (`pyset_and`/`pyset_or`/`pyset_xor`/`pydict_or`) are checked
first, so `{1,2} & {2,3}` and `{"a":1} | {"b":2}` are untouched.

A first cut reused `PyNotOrderableError` and produced a message about
`__lt__/__gt__` for a bitwise operator — corrected to its own helper before
landing.

### Verification

`test/test_nilpy_dunder_bitwise.npy`, byte-identical to CPython: all five
dunders, the no-dunder case for `&` and `<<` caught as `TypeError` (not a crash,
and not a compile error), set `&`/`|`/`^`, dict `|`, and plain integer bitwise
ops unaffected.

### Found while writing that test — a separate, pre-existing bug

The test initially failed for an unrelated reason: its dunder parameter was
named `o` and so was the module-level variable. A method parameter whose name
matches a module-level variable silently strips that variable's class type at
operator-dispatch sites, so no dunder dispatches at all. Reproduced on the
pinned v239 binary, so it long predates this work — filed as
[[bug-nilpy-global-shadowed-by-method-param-name-loses-class-type]] (prio 75).
The test now uses `rhs`, with a comment saying why.
