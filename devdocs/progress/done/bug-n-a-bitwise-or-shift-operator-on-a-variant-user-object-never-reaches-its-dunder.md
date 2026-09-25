---
track: N
prio: 45
type: bug
blocked-by: []
summary: "FIXED 2026-09-25. With a VARIANT operand, `<<`/`>>` and `@` call the user dunder or its reflected form; `@` otherwise raises TypeError. The augmented `&= |= ^= <<= >>= @=` try the in-place dunder first and mutate a set or dict in place. A statically class-typed RIGHT operand (`12 & c`) calls __rand__ and friends. set.add returns None. Every shape is diffed against CPython in test_nilpy_bitwise_and_shift_on_a_variant_operand."
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
blocks). **There is no such arm for `&`, `|`, `^`, `<<`, `>>`.**

**Verified by dumping the IR of both, rather than inferred** — an earlier draft
of this ticket said the node lowers to a raw `IR_BINOP` over the operand's
handle, and that was wrong. `PXXDBG=a.ir:f` on `return c - 12` and
`return c & 12`, same class, same receiver:

    c - 12    ->  call <pysub_v>                    (the dispatch arm)
    c & 12    ->  var_binop  ... (no pylib call)    (the generic fallback)

So it reaches **`IR_VAR_BINOP`**, the generic variant-operator path, which
coerces both operands numerically. That is why `& | ^` answer a plain int
(silent) and `<< >>` raise RunError 219 — a coercion refusing an object, not a
pointer being used as a number. The distinction matters for the fix: the value
is not garbage, it is a *correct* numeric answer about the wrong thing.

`pybitand_v`, `pybitor_v`, `pybitxor_v`, `pyshl_v` and `pyshr_v` already exist
in `pylib.pas` — they are what `pyeval` uses. **Verified: nothing in `ir.inc` or
`pyparser.inc` references any of the five**, so the lowering never calls them;
and each is a one-line `pyvar_of_int(pyvar_to_int(a) <op> pyvar_to_int(b))` with
no `PyVarUserArith` try, unlike every arithmetic helper.

**Open question, stated as one:** the `c & 12` IR also carries a guarded runtime
call before the `var_binop` which `c - 12` does not need. Whatever that guard
tries, it does not admit `&` — a class declaring `__and__` still gets the
numeric answer. Worth identifying before adding the arm, in case the arm belongs
there instead.

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

## Addendum 2026-09-15 — `@` is the same gap, one operator over

Measured while fixing
`bug-n-annotating-a-dunder-operand-breaks-the-operator-on-a-variant-receiver`:
`h.a @ h.b` with `h` a bare parameter raises `unsupported operand type(s) for
this operator` with a BARE `def __matmul__(self, o)`, while `a @ b` on
statically typed locals answers 12.0. `compiler/builtin/pylib.pas` has no
`__matmul__` string anywhere — the variant `@` entry point never consults a
user dunder, exactly like the five bitwise/shift operators this ticket names.
The parser side is wired (`PyBinOpDunderName` maps `tkAt`), so it is the
runtime arm only, and the fix shape is the one the arithmetic entry points
already have: `if PyVarUserArith(a, b, '__matmul__', '__rmatmul__', Result)
then Exit;` at the top of the variant `@` routine. Not fixed in that commit
because the dispatch ticket's fixture had to stay about dispatch; six
operators now share this ticket.

## Addendum 2026-09-25 (frankB): `& | ^` fixed; shifts, augmented and reflected-static are still open

- **What landed.** `PyParseBitAnd/Xor/Or` now route a pair with a VARIANT operand
  to `pybitand_v/pybitxor_v/pybitor_v` (`PyBitVariantCall`, in `pyparser.inc`).
  The IR arm this ticket proposed is not used, and that is deliberate. At IR
  level `tkAnd`/`tkOr` with a variant operand also covers the synthesized
  boolean `and`/`or` nodes (`PyParseBoolExpr` builds a `tkOr` AN_BINOP), so the
  parser is the one place that only sees the operator.
- **The helper order.** Each helper tries, in order:
  1. `PyVarUserArith`, the dunder and its reflection;
  2. `PyVarSetOp`: set with set through `pyset_*`, dict | dict through
     `pydict_or`, TypeError for any other object;
  3. bool with bool, giving a bool;
  4. `PXXPromoVarArithTry` with the inline path's op codes 6, 7 and 8, so a big
     int stays exact;
  5. the machine-int fallback.
  `pysub_v` got the `PyVarSetOp` arm too, for set `-`.
- **Measured.** `test/test_nilpy_a_bitwise_operator_on_a_variant_dispatches_on_its_type.npy`
  diffs the plain operators against CPython's output: int, big int, negative,
  bool, dunder (with `__ror__` through a variant), set, set with a literal,
  dict, a list that must raise, and a loop. Every row matches at HEAD. Pin v433
  diverges from the bool row on.
- **Still open.** `<<` and `>>` are not routed. The augmented forms need
  in-place twins, because `s |= t` must mutate the set the other names see, and
  routing them to the plain helper would rebind to a new set. `12 & c` with `c`
  statically class-typed never enters these helpers (neither operand is a
  variant) and segfaults, the same on the pin: the static dunder dispatch
  (`PyBitDunder`) only tries the LEFT operand's class.
- **This ticket's repro is not the variant case today.** The `p_and(c)`
  parameter is call-site-typed as `C`, so `c & 12` already reaches `__and__`
  statically on pin v433 (it prints 4). The variant shape is an operand that
  comes out of a list, which is what the fixture uses.


## Resolution (2026-09-25, frankS)

- The shifts: pyshl_v/pyshr_v try PyVarUserArith before the promo shift (ops 9/10). PyParseShift routes a variant operand to them.
- Augmented `& | ^ << >>`: PyAugMarkedTok marks them on a variant target, and the IR arm calls pyaug{bitand,bitor,bitxor,shl,shr}_v. Each helper tries the in-place dunder, then does a set/dict in-place update (PyVarSetAugInPlace), then falls back to the plain helper.
- `@` / `@=`: a variant operand goes to pymatmul_v / pyaugmatmul_v, from the pasparser_expr `@` arm and from both `@=` sites.
- `12 & c`: PyBitDunder takes the reflected `__r<op>__` when only the right operand is a user class. It used to call the left operand's dunder on an int and segfault.
- set.add returns None. The literal and comprehension desugars call the new add_self.

Fixed in commit 4a4167bc65.
