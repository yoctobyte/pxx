---
slug: bug-a-a-variant-comparison-does-not-coerce-a-stringy-operand
track: A
prio: 45
type: bug
status: done
blocked-by: []
summary: "`a := 1; b := '1'; a = b` answers False and `1 < '2'` answers False; FPC coerces the stringy side and answers True for both. SILENT wrong boolean. PXXVarBinOpPas coerces for arithmetic (isCompare=0) and not for comparison, and x86-64 hand-emits its own copy of the whole rule in EmitVarBinOp — so the fix is two places, or one after deleting the duplication."
owner: claude-A
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

## FIXED 2026-08-23 (claude-A)

All four rows of the symptom, plus 17 more, now match `fpc 3.2.2 -Mobjfpc -O1`
on x86-64, i386, aarch64 and arm32 alike.

### The rule, written once per implementation

Comparison coerces **only when EXACTLY ONE side is stringy**:

| operands | behaviour |
| --- | --- |
| both stringy | string comparison (`'ab' < 'ac'`), unchanged |
| exactly one stringy | convert the text, compare numerically |
| neither | numeric comparison, unchanged |

That third-case symmetry is what makes it safe: `PXXVarNumCoerce` returns a
non-stringy operand untouched, so "coerce both" and "coerce the one" are the
same call. And when the text does not parse it RAISES, which is FPC's answer for
`v('ab') = v(2)` — the ticket's fourth row, where pxx used to answer `False`.

### What the investigation above got wrong, and it mattered

The recommendation was to route Pascal's variant binop through
`PXXVarBinOpPas` and delete the x86-64 arm. That is still the right *direction*,
but the ticket's own "read this before choosing option 2" section is the
operative one: the two implementations are **not equivalent** and the inline
emitter is load-bearing for NilPy. So this fix does neither option 1 nor option
2 as written.

What it does instead is narrower and came out of measuring rather than reading:

1. **`PXXVarBinOpPas`** (`compiler/builtin/builtin.pas`) — the `isCompare = 0`
   guard gained an `else` arm carrying the one-stringy rule. Straightforward;
   this is the half the ticket predicted.

2. **`EmitVarBinOp`** (`compiler/ir_codegen.inc`) — the first attempt widened
   the guard on the EXISTING coercion block and **changed nothing**. The reason
   is placement, and it is the whole content of this fix: that block sits on the
   NUMERIC path, *after* the string dispatch at the top of the emitter — and
   that dispatch takes its string arm as soon as **either** side is stringy,
   then answers "different tags → not equal" and never reaches the coercion. So
   the comparison coercion had to be emitted **before** the string dispatch,
   with a run-time guard (`(lTag stringy) XOR (rTag stringy)`, computed as
   `tag - VT_CHAR <= 1` unsigned on each side) — the "exactly one" condition is
   a property of the tags, not of the opcode, so it cannot be a compile-time
   test the way the arithmetic one is.

   Measured, not reasoned: the first version passed a hand-written repro's
   *arithmetic* rows (`'15' - 3` = 12, so the helper was linked and the block
   was running) while every comparison row stayed `FALSE`. That contradiction is
   what located the placement.

3. **The emission is now shared.** The nine-instruction save/call/call/restore
   sequence was hoisted into `EmitVarNumCoercePair(vcProc)` and both call sites
   use it. The two sites disagree about *when* to coerce and agree about *how*
   — which is the split the code now expresses, instead of two copies of the how.

### What was NOT done, deliberately

The Pascal-vs-NilPy split at the lowering seam (option 2's revised form) is
still unbuilt, and `EmitVarBinOp`'s `not PyProgramMode` arms are still live.
This fix keeps both implementations and makes them agree; it does not remove the
duplication. That remains the right follow-up and the ticket's analysis of it
stands — but it is a codegen change wanting the full matrix, and it was not
needed to make the four rows correct. **The new test is the thing that notices
if they drift again**, which the previous drift did not have.

### Verified

- `test/test_variant_comparison_coerces_a_stringy_operand.pas`, wired into
  `test-core`: 28 assertions — 11 mixed-operand comparisons, 5 both-stringy,
  5 neither-stringy, 7 arithmetic rows guarding the coercion move (`'5' + '3'`
  must still concatenate). `ALL OK` under pxx x86-64, pxx i386,
  pxx aarch64 (qemu), pxx arm32 (qemu) and fpc 3.2.2.
- A 21-row differential program: pxx x86-64, pxx i386 and fpc produce
  **identical output line for line**.
- `v('ab') = v(2)` raises `EVariantError` under both (message and exit code are
  ours by the `--strict-fpc` scope rule — 219 vs FPC's 217).
- NilPy untouched: the comparison block is behind `not PyProgramMode`, and a
  `.npy` probe over `1 == "1"`, `0 == None`, `None == None`, `"5" + "3"`,
  `"x" == 120` matches CPython exactly.
- Self-host fixedpoint converged in one round.

### Side finding, not filed as a blocker

**riscv32 has no Variant support at all** — `var_store` is an unsupported node
in its codegen, so `var v: Variant; v := 1` does not compile there, with HEAD or
with the pinned binary. The ticket lists riscv32 among the targets that "route
through `PXXVarBinOpPas`"; nothing routes anywhere, because nothing compiles.
Pre-existing and unrelated to this fix, but it means the cross-target agreement
claimed here covers four targets, not five.

## Gate

`make compiler/pascal26` converged + the differential above + `tools/gate.sh quick`.

## Log
- 2026-08-23 — resolved, commit PENDING-COMMIT.
