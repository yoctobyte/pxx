---
slug: bug-a-null-does-not-propagate-through-variant-arithmetic
track: A
prio: 45
type: bug
status: done
blocked-by: []
summary: "`Null + 5` yields 5, not Null: VarIsNull(a + b) with a = Null answers False where FPC answers True. Null is read as payload 0 and behaves like the number zero through every arithmetic operator, so a missing value silently becomes a real one — the exact failure mode Null exists to prevent."
owner: claude-A
---

# Null does not propagate through Variant arithmetic

```pascal
var a, b, c: Variant;
begin
  a := Null; b := 5;
  c := a + b;   WriteLn(VarIsNull(c));   { fpc: TRUE   pxx: FALSE }
  c := a * b;   WriteLn(VarIsNull(c));   { fpc: TRUE   pxx: FALSE }
end.
```

PXX reads `VT_EMPTY`'s payload as 0 and carries on, so `Null + 5` is `5` and
`Null * 5` is `0`. **A missing value silently becomes a real one**, which is the
single failure mode Null exists to prevent. Every database-shaped program is
exposed: a Null column summed into a total contributes 0 and the total looks
plausible.

This is a genuine three-valued-logic gap, not a formatting difference. FPC's
rule (inherited from OLE and shared with SQL): any arithmetic operator with a
Null operand yields Null.

## What is already right

`VarIsNull` and `VarIsEmpty` themselves are correct, and `Null` assigns and
round-trips correctly — the tag is stored and read faithfully. Only the
operators ignore it. Comparison is a separate question and is NOT part of this
ticket: `a = b` with a Null answers False in both implementations (FPC's
`VarCompareValue` has `vrNotEqual` for it), so that row already agrees.

## Where to fix it

Same two-implementation problem as
[[bug-a-a-variant-comparison-does-not-coerce-a-stringy-operand]]: the rule
belongs in `PXXVarBinOpPas` (`compiler/builtin/builtin.pas`, the path for
i386/arm32/aarch64/riscv32) **and** in x86-64's hand-emitted `EmitVarBinOp`.
Fixing these two tickets together is strictly cheaper than fixing them apart —
they are the same function, the same guard region, and the same "which
implementation is authoritative" decision. If that decision goes the recommended
way (delete the x86-64 arm, route everything through the helper), both become
one small change in one file.

An early `if either tag = VT_EMPTY then result := Null; exit` in the arithmetic
path is the whole rule. Take care that it runs BEFORE the stringy coercion —
`PXXVarNumCoerce` on a Null must not turn it into 0 first, which is arguably
where the current behaviour comes from.

`VT_EMPTY` currently spells both `Unassigned` and `Null` in this
implementation; FPC distinguishes them (`varEmpty` vs `varNull`) and propagates
only the latter, so whoever takes this should check whether a separate tag is
needed before writing the propagation rule. If it is, that is the real first
step and is worth its own note in this ticket.

Found by the Variant differential family, 2026-08-22.

## Gate

Track A's, plus `+ - * /` and `div`/`mod` with a Null on each side matching
fpc 3.2.2, a row proving `Unassigned` still behaves as it does today, and a
cross-target run.

## FIXED 2026-08-23 (claude-A)

Landed with [[bug-a-a-variant-comparison-does-not-coerce-a-stringy-operand]]'s
follow-up, in the same guard region of the same two functions — which is what
this ticket predicted would be cheaper, and was.

### The tag question, answered by measuring instead of designing

The ticket asked whether a separate `VT_NULL` tag is needed first, since
`VT_EMPTY` spells both `Null` and `Unassigned` here. **It is not**, and the
reason is a fact about FPC that the ticket assumed the other way:

```
fpc 3.2.2:  Unassigned + 5  ->  VarIsEmpty = TRUE   (NOT 5)
            Null       + 5  ->  VarIsNull  = TRUE
```

FPC propagates **both**, each as itself. So one tag propagating produces the
right ANSWER for both spellings, and the only residual difference is which of
`VarIsNull`/`VarIsEmpty` says True afterwards — an approximation that is
pre-existing and already documented in `lib/rtl/variants.pas`' own header
("VarIsNull and VarIsEmpty are the same question here"). A `VT_NULL` tag would
sharpen that, and it is a real change (VT_EMPTY = 0 is NilPy's `None`, used in
~40 places, and it is part of `PXX_RUNTIME_LAYOUT`); it is not needed for this
defect and was not attempted. Recording it so the next session does not redo the
same investigation.

### Both implementations

- **`PXXVarBinOpPas`** (`compiler/builtin/builtin.pas`, the i386/arm32/aarch64
  path): an early `if (isCompare = 0) and (either tag = VT_EMPTY)` arm writes
  `VT_EMPTY` into `dest` and returns it. Placed **before** the stringy coercion
  exactly as the ticket advised — a Null is not stringy, so `PXXVarNumCoerce`
  would hand it back untouched and the numeric dispatch would then read the 0
  payload, which is where the old behaviour came from.
- **`EmitVarBinOp`** (`compiler/ir_codegen.inc`, x86-64 inline): the same test
  emitted at the top of the arithmetic path — before the string dispatch too,
  because `Null + 'x'` is Null as well. Clears the destination variant
  (`EmitVariantClear`, so a managed string already in the result slot is
  released), stores `VT_EMPTY`/0, and jumps to `L_all_done`.

Both are behind the same `not isCompare` guard, and the emitter's is also behind
`not PyProgramMode`: `None + 5` is a TypeError in Python, not a value.

### Comparison stayed out, and is now asserted

The ticket was explicit that comparison is a separate question and already
agrees. Three rows in the new test pin that down (`Null = 5` False,
`Null <> 5` True, `5 = Null` False) so a future widening of the propagation rule
cannot quietly take them with it.

### Verified

- `test/test_variant_null_propagates_through_arithmetic.pas`, wired into
  `test-core`: 21 assertions — 8 with Null on the left (`+ - * / div mod`, plus
  `Null + 2.5` and `Null + 'x'`), 4 with Null on the right, 1 with both, 3
  comparison rows, and 3 ordinary-arithmetic rows proving payload 0 is still a
  value (`0 + 5` is 5, not Null — the guard must test the TAG, not the payload).
  `ALL OK` under pxx x86-64, i386, aarch64 (qemu), arm32 (qemu) and fpc 3.2.2.
- NilPy unaffected: a `.npy` probe over `None == 5`, `None != 5`, `x is None`,
  `d.get(missing)`, `5 + 3`, `"a" + "b"` matches CPython exactly.
- Self-host fixedpoint converged in one round.

### Two things found alongside, filed separately

- **riscv32 cannot compile a Variant at all** —
  [[bug-a-riscv32-codegen-has-no-variant-support]]. This ticket's gate asks for
  "a cross-target run"; that run covers four targets, not five, and the fifth is
  not a variant-rule question.
- **`string(Null)` renders as `None`** in pxx (a NilPy-ism reaching Pascal
  output) where FPC raises `EVariantTypeCastError`. Pre-existing — identical
  under the pinned binary — and unrelated to propagation. Filed as
  [[bug-a-a-null-variant-renders-as-none-in-pascal]].

## Gate

`make compiler/pascal26` converged + the differential above + `tools/gate.sh quick`.

## Log
- 2026-08-23 — resolved, commit 9074403c0.
