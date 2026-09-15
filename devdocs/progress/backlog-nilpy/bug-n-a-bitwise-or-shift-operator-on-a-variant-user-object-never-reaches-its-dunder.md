---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`c & 12` where c reads as a VARIANT holding a user object never reaches __and__: it coerces the object to an int instead. Same for |, ^, << and >>. This is what blocks the augmented halves &=, |=, ^=, <<= and >>=."
---

# `&`, `|`, `^`, `<<`, `>>` on a variant user object skip the dunder

```python
class C:
    def __init__(self, v):     self.v = v
    def __and__(self, o):      return C(self.v & o)
    def __lshift__(self, o):   return C(self.v << o)

def p_and(c):   return (c & 12).v      # CPython 4    pxx AttributeError: 'int' object has no attribute 'v'
def p_shl(c):   return (c << 2).v      # CPython 80   pxx Runtime error 219 (not convertible to an integer)

print(p_and(C(20)), p_shl(C(20)))
```

Measured 2026-09-15 against CPython, one row per operator. The seven ARITHMETIC
operators (`+ - * / // % **`) all reach their dunder correctly on the same
receiver; the five bitwise/shift ones do not. `&`, `|` and `^` answer a plain
int (silent); `<<` and `>>` die with RunError 219 (loud).

## Mechanism

`IRLowerAST`'s variant-dispatch arms cover `+`, `-`, `*`, `/`, `//`, `%` and the
four orderings (`ir.inc`, the `pyadd_v`/`pysub_v`/`pymul_v`/`pyfloordiv_v`
blocks). **There is no such arm for `&`, `|`, `^`, `<<`, `>>`**, so the node
lowers to a raw `IR_BINOP` over the operand's HANDLE.

`pybitand_v`, `pybitor_v`, `pybitxor_v`, `pyshl_v` and `pyshr_v` already exist
in `pylib.pas` — they are what `pyeval` uses — and they coerce through
`pyvar_to_int`, which is the 219. So the runtime helpers are present and the
LOWERING never calls them; and none of the five tries `PyVarUserArith` first,
which is what the arithmetic helpers do.

This is the same shape as
[[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]], which is the
ticket that added the `-` and `/` arms. The bitwise family was not in it.

## Why it is filed rather than fixed

It is the BLOCKER under
[[bug-n-augmented-assignment-to-an-unannotated-parameter-silently-loses-the-mutation]],
whose augmented halves `&=`, `|=`, `^=`, `<<=`, `>>=` cannot be repaired from
above: the augmented marker selects a `pyaug<op>_v` from the variant-dispatch
arm, and for these five there is no arm to select from. `PyAugMarkedTok` in
`pyparser.inc` names them and says so.

Fixing this one delivers both — the plain form and, with a `pyaug<op>_v` twin
and a row in `PyAugMarkedTok`, the augmented form.

## Shape of a fix

Three parts, none large:

1. `PyVarUserArith(a, b, '__and__', '__rand__', Result)` as the FIRST line of
   each of the five `py*_v` helpers, exactly as `pysub_v`/`pymul_v` already do.
2. An IR arm routing `tkAmp`/`tkPipe`/`tkXor`/`tkShl`/`tkShr` to them when
   either operand reads as a variant. The `//`/`%` block is the template.
3. `pyaugbitand_v` &c., each trying `__iand__` then calling the plain twin, plus
   the five tokens added to `PyAugMarkedTok`.

**Beware the token spelling**, and `PyBinOpDunderName`'s own comment says why:
in the raw NilPy stream a bare `&` is `tkAmp` and a bare `|` is `tkPipe`, while
`tkAnd`/`tkOr` are the `and`/`or` KEYWORDS with no dunder at all. `PyAugBinTok`
normalises `&=` to `tkAnd`, so the augmented and plain sides key on DIFFERENT
tokens for the same operator. Delegating one to the other is the trap.

## Gate

`.npy` diffed against CPython: each of the five operators plain and augmented,
on a variant receiver; a variant holding an int must keep its ordinary bitwise
answer; `set |= set` and any other pylib-owned class must be unaffected
(`PyVarUserObj` excludes them, which is the existing guard).
