---
track: A
prio: 65
type: bug
summary: "NilPy: `//`, `%`, ordering comparisons, float(), max/min and sorted() narrow a Variant-held arbitrary-precision int through pyvar_to_int — (2**64+5) // 1 prints 5; the promo guards test the STATIC type, which is tyVariant, so they never fire"
---

# `//`, `%`, ordering and `float()` narrow a Variant-held bignum

- **Type:** bug (silent wrong value) — **Track A** (the fix is in the shared
  `compiler/ir.inc` lowering and `compiler/builtin/pylib.pas`; the semantics
  are NilPy's)
- **Found:** 2026-08-06, bughunting, `tools/pydiff.py` against CPython.

## Measured (self-hosted binary at `412fda7a3`)

```python
x = 2**64 + 5
print(x)                 # CPython 18446744073709551621   pxx 18446744073709551621  OK
print(x + 1)             # correct                        OK   (pyadd_v -> promo)
print(x * 2)             # correct                        OK   (pymul_v -> promo)
print(x == 2**64 + 5)    # correct                        OK

print(x // 1)            # CPython 18446744073709551621   pxx 5
print(x // 3)            # CPython 6148914691236517207    pxx 1
print(x % 7)             # CPython 0                      pxx 5
print(x % (2**64))       # CPython 5                      pxx ZeroDivisionError

y = 2**64
print(y > 5)             # CPython True                   pxx False
print(y < 5)             # CPython False                  pxx True
print(y >= 5)            # CPython True                   pxx False
print(float(y))          # CPython 1.8446744073709552e+19 pxx 0.0
print(max(y, 5))         # CPython 18446744073709551616   pxx 5
print(sorted([2**65, y, 5]))
                         # CPython [5, 2**64, 2**65]      pxx [2**65, 2**64, 5]
```

`x // 1 == 5` is the sharp one: the dividend alone is enough to show the value
is narrowed **before** the division. Every wrong answer is the correct operation
applied to `operand mod 2^64`. `x % (2**64)` raises only because the *divisor*
narrows to 0 — both operands are narrowed, not just one.

Local and module scope, literal and runtime-built operands all behave the same.

## Cause — measured

`PXXDBG=a.ast` on `def loc(): x = 2**64 + 5; y = x // 1` shows the binop node and
both operands carry `tk=22` — **`tyVariant`** (defs.inc:895), not
`tyPromoInt64`. The value is a bignum living in a Variant payload, which is the
normal shape for a NilPy module-scope binding or inferred local.

Both NilPy lowering arms that handle these operators guard on the **static**
type:

- `compiler/ir.inc:6482` — the `//`/`%` arm routes to `pyfloordiv_i` /
  `pyfloormod_i` (**Int64 in, Int64 out**) unless
  `TypeIsPromoInt(ASTTk[node])`, `…[ASTLeft]` or `…[ASTRight]`. Its comment
  states *"Both operands are checked, not just the node, so a promo operand
  cannot be narrowed into the Int64 helper either"* — true for a **statically**
  promo-typed operand, but `TypeIsPromoInt(tyVariant)` is False, so a
  Variant-held bignum walks straight into the Int64 helper.
- the same shape defeats the ordering-comparison and `float()` paths, which is
  why `>` `<` `>=` `<=` are wrong while `==` (a different arm) is right.

The narrowing itself is then explicit in the runtime:
`compiler/builtin/pylib.pas:4757` and `:4790`

```pascal
r^.Payload := pyfloordiv_i(pyvar_to_int(a), pyvar_to_int(b));   { pyfloordiv_v }
r^.Payload := pyfloormod_i(pyvar_to_int(a), pyvar_to_int(b));   { pyfloormod_v }
```

## The fix is a pattern already in the file

`pyadd_v`, `pysub_v` and `pymul_v` each consult the promo runtime *first* and
only fall through when neither side is promo-tagged
(`pylib.pas:4910`, `:4977`, `:4553`):

```pascal
if PXXPromoVarArithTry(@Result, @a, @b, 1) <> 0 then Exit;
```

`pyfloordiv_v` / `pyfloormod_v` are missing exactly that line, and the
comparison / `float()` paths want the equivalent (`PXXPromoVarCmpTry`,
`PXXPromoToDouble`). The `IR_VAR_BINOP` path at `ir.inc:6637`–`6700` already
wires both Try-helpers correctly — it is simply never reached, because the
NilPy-specific arm at `:6482` fires ahead of it.

**One real trap, not a detail:** `PXXPromoVarArithTry`'s op 4 / op 5 are
`PXXPromoDiv` / `PXXPromoMod`, which are Pascal-**truncating**. Python's `//`
and `%` **floor**. promocore already has `PXXPromoFloorDiv` / `PXXPromoFloorMod`
for this and the header comment says why they are separate entry points. So the
fix needs new op codes for the floor pair rather than reusing 4/5 — reusing them
would trade a loud wrong answer for a quiet one on negative operands, which is
the exact failure `PromoOpHelper` was written to avoid.

## Related

- [[bug-nilpy-augmented-assignment-truncates-to-32-bits]] — different root cause
  (32-bit binding), same "ordinary arithmetic silently wrong" class.
- [[bug-nilpy-int-of-a-long-decimal-string-narrows]] — the parse-side sibling.
- [[bug-nilpy-class-field-and-recursive-return-narrow-an-arbitrary-precision-int]]
  (done) — the previous narrowing sweep; these are sites it did not cover
  because they are Variant-held rather than statically typed.

## Gate

Per-fix loop. A `.npy` test diffing `//`, `%`, `< <= > >=`, `float()`, `max`,
`min` and `sorted` over operands straddling 2^63 and 2^64 — **including negative
operands**, to pin the floor-vs-truncate rule — against CPython via
`tools/pydiff.py`.
