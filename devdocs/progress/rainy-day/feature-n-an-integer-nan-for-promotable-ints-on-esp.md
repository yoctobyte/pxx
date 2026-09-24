---
track: N
prio: 20
type: feature
blocked-by: []
summary: "NOT to be implemented until the owner lifts it. On ESP, a NilPy promotable-int `//` or `%` by zero would produce an integer NaN (a third promo tag) that propagates, compares false and prints `nan`, instead of halting or answering 0. The owner called it a valid construct for promotable ints and said not to fix it now. The real work is the BOUNDARY LIST: every consumer that has no NaN (indexing, range, slicing, truthiness, dict keys, Pascal/C arguments, formatting, int-to-float) needs a decided answer, and none is decided here."
---

# An integer NaN for promotable ints on ESP

Filed 2026-09-24 (frankb-12) at the owner's direction, relayed by the
coordinator. **Deferred, not scheduled.**

## The owner's words

On ESP a math error must never halt: *"an embedded device that should (try) to
keep running, even if whatever unexpected input (sensor etc) produces a math
error"*. On the int-NaN idea: *"for promotable int, this would be a valid
construct"*, and *"dont fix it now"*. The interim answer, int div/mod by zero ->
0 on ESP, is franks-a3's, in progress now.

## Mechanism

A third tag in `compiler/builtin/promocore.pas`: `PROMO_TAG_NAN = 2`, beside
`PROMO_TAG_INLINE = 0` and `PROMO_TAG_HEAP = 1` (the same constants are in
`compiler/defs.inc`). `//` and `%` by zero produce it; every arithmetic op with
a NaN operand yields NaN; comparisons are false; `str()` prints `nan`.

**Checked against the code, and HALF right.** There is no compiler-emitted fast
path: every promo operation is a call into promocore, and the fast path is the
runtime's own test, both tags INLINE -> native arithmetic (e.g.
PXXPromoCmp, PXXPromoFloorDiv). A NaN operand fails that test, so the fast
path costs nothing: true. But the SLOW paths decide inline-vs-heap as "INLINE,
else HEAP" at several of promocore's 33 `SlotTag` tests. Examples:
PXXPromoToInt64 (~2035), PXXPromoToDouble (~2128), the shift-count reader
(~1433/1454/1459), and the big-number loaders (~1582/1592/2009). As written,
each of those would read a NaN payload as a bignum POINTER. Every one needs a
NaN arm. PXXPromoClear (`= PROMO_TAG_HEAP` -> free) is already safe.

## Scope

- **NilPy only.** A Pascal `Int64` has no spare bit pattern; only the promo
  slot has a tag word to spend.
- **ESP only.** The desktop keeps ZeroDivisionError, as CPython does.

## The boundary list (found, NOT decided)

Every place an int-NaN meets a consumer that has no NaN:

1. **To a machine int**: PXXPromoToInt64 / ToInt64Wrap / FitsInt64. This one
   covers indexing `xs[n]`, `range(n)`, slice bounds, `len`-style arguments,
   and repeat counts (`s * n`).
2. **Pascal / C call arguments** that take an Int64 or smaller (the same
   conversion, but the callee cannot be told).
3. **Truthiness** `if n:`. Float NaN is truthy in CPython, but that is not
   necessarily the right answer for an int.
4. **Comparison**: PXXPromoCmp returns -1/0/1 and has no "unordered" result.
   `==`, `<` and sorting all go through it.
5. **Dict keys / hash / `in`**: NaN != NaN breaks lookup of its own key.
6. **Formatting**: `str`/`repr` (`nan`), `%d`, `format(n, 'x')`, and
   PXXPromoToBase (hex/oct/bin).
7. **int -> float**: PXXPromoToDouble. The natural answer is float NaN, the
   one boundary with an obvious mapping.
8. **Into a Variant**: PXXPromoToVariant has no int-NaN tag to box as.
9. **Bitwise and shifts**: `&`, `|`, `^`, `<<`, `>>`, including NaN as a SHIFT
   COUNT.
10. **Parsing back**: `int("nan")` and PXXPromoFromStr.
11. **Struct / bytes packing and JSON** (`struct.pack`, `int.to_bytes`).

Retire when the owner lifts the deferral and each row above has an answer.
