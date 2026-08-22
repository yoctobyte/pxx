---
slug: bug-a-a-variant-comparison-does-not-coerce-a-stringy-operand
track: A
prio: 45
type: bug
status: backlog
blocked-by: []
summary: "`a := 1; b := '1'; a = b` answers False and `1 < '2'` answers False; FPC coerces the stringy side and answers True for both. SILENT wrong boolean. PXXVarBinOpPas coerces for arithmetic (isCompare=0) and not for comparison, and x86-64 hand-emits its own copy of the whole rule in EmitVarBinOp — so the fix is two places, or one after deleting the duplication."
---

# A Variant comparison does not coerce a stringy operand

```pascal
var a, b: Variant;
begin
  a := 1;    b := '1';  WriteLn(a = b);    { fpc: TRUE   pxx: FALSE }
  a := '1';  b := 1;    WriteLn(a = b);    { fpc: TRUE   pxx: FALSE }
  a := 1;    b := '2';  WriteLn(a < b);    { fpc: TRUE   pxx: FALSE }
  a := 'ab'; b := 2;    WriteLn(a = b);    { fpc: raises EVariantError
                                             pxx: FALSE }
end.
```

**Silent wrong boolean**, which is the worst shape: the comparison does not
fail, it answers, and it answers the safe-looking `False`. A program filtering
records on `v = 1` where the variant arrived from text (a config value, a
database column, a parsed field) simply matches nothing.

The last row is the same defect wearing a different hat: PXX answers `False`
where FPC raises. Refusing to compare incomparables is a real answer; silently
saying "not equal" is not.

## Where it lives, and why it is two places

`PXXVarBinOpPas` (`compiler/builtin/builtin.pas`) already holds the rule — for
arithmetic only:

```pascal
if isCompare = 0 then
begin
  ...
  lp := PXXVarNumCoerce(left, @la);
  rp := PXXVarNumCoerce(right, @ra);
end;
Result := PXXVarBinOp(dest, lp, rp, opTk, isCompare);
```

The `isCompare = 0` guard is the bug in that file. But that helper is the path
for **i386, arm32, aarch64 and riscv32**; x86-64 hand-emits the same logic in
`EmitVarBinOp` (`compiler/ir_codegen.inc`, ~line 3300), where the compare arm
tests tags for equality and jumps to `L_diff_tags` when they differ.

That duplication has already produced one drifted pair — the string-arithmetic
defect was fixed in the x86-64 emitter on 2026-08-20 and separately in the
helper as `bug-a-pxxvarbinop-carries-the-same-string-arithmetic-defect-as-x86-64-did`.
This would be the second time the same rule is fixed twice.

## Two ways to take it, and a recommendation

1. **Patch both.** Drop the `isCompare = 0` guard (coerce for comparison too,
   with the FPC rule that a non-parsing string against a number raises rather
   than answers), and hand-emit the same coercion in the x86-64 compare arm.
   Smaller diff, keeps the fast path, **guarantees a third drift.**
2. **Route x86-64's Pascal variant binop through `PXXVarBinOpPas` and delete
   `EmitVarBinOp`'s Pascal arm.** One implementation of one rule. Costs a call
   per variant binop on the target where variants are least likely to be hot,
   and it is a real codegen change needing the full gate.

**Recommended: 2.** The measurement to take first is what `EmitVarBinOp` costs
versus the call — if variant binops are already helper calls on four of six
targets, the sixth is not carrying a load-bearing optimisation, it is carrying a
second spec. `devdocs/dev/normalise-dont-special-case.md`; note that this pair
has drifted once already, which is the evidence the doc asks for.

`VarCompareValue` in `lib/rtl/variants.pas` has its own comparator with
`IsTextTag`, and its header comment already documents the intended rule —
*"text that will not parse, against a number: EVariantError"* — so the SPEC is
written down and only the two operator paths disagree with it. Whoever takes
this should check whether `VarCompareValue` can simply become the one
implementation.

Found by the Variant differential family, 2026-08-22, alongside
[[bug-a-a-char-variant-converts-to-its-ordinal-not-its-text]] (fixed) and
[[bug-a-null-does-not-propagate-through-variant-arithmetic]].

## Gate

Track A's, plus the four rows above matching fpc 3.2.2, and a cross-target run
(the two implementations must agree with each other, which is the property that
has already failed once).

## Read this before choosing option 2 — four prior substitutions failed

`compiler/ir.inc` around `IRPyVarEqFallback` already carries the warning, from
someone who tried:

> `IR_VAR_BINOP` is not a routine to be swapped out. On x86-64 it is INLINE
> emitted code (EmitVarBinOp) carrying its own None-equality arm, its own
> char/string arms and its own numeric double-dispatch; builtinheap's
> PXXVarBinOp is a DIFFERENT implementation of the same operator for the other
> backends. Substituting either one for the whole fallback broke, in order:
> promotable ints, `is` vs `==`, char-vs-string, and `0 == None`.

So the two implementations are not merely duplicated, they are **not
equivalent**, and the x86-64 one is load-bearing for NilPy — which is also where
variants are hot, since NilPy uses them as its universal value type. That is the
real reason the hand-emitted version exists, and it is a good one.

This changes the recommendation's shape without changing its direction:

- **Do not** replace `IR_VAR_BINOP` wholesale. That is the move that failed four
  times.
- **Do** split by language at the lowering seam, which is where every other
  Pascal-vs-NilPy variant divergence is already decided (`IRLowerVariantAsScalar`
  picks its helper set there; i386 picks `PXXVarBinOpPas` vs `PXXVarBinOp`
  there). Pascal routes to the helper; NilPy keeps the inline emitter and its
  performance. Then the Pascal rule exists once, `pasPlus` and the other
  `not PyProgramMode` arms inside `EmitVarBinOp` become dead and can be removed
  in a separate, purely subtractive commit.
- Measure first: confirm no Pascal-side test loses meaningfully on a variant-
  heavy loop. Pascal variants are cold in a way NilPy's are not, which is the
  asymmetry that makes this safe on one side and not the other.

Investigated to this depth on 2026-08-22 and deliberately NOT attempted in that
session: the entanglement above is exactly the "the overhaul is often the
smaller job — except when it is not" case in
`devdocs/dev/root-cause-over-microfix.md`. Diagnosis banked, work parked.
