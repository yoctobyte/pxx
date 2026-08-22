---
slug: bug-a-null-does-not-propagate-through-variant-arithmetic
track: A
prio: 45
type: bug
status: backlog
blocked-by: []
summary: "`Null + 5` yields 5, not Null: VarIsNull(a + b) with a = Null answers False where FPC answers True. Null is read as payload 0 and behaves like the number zero through every arithmetic operator, so a missing value silently becomes a real one — the exact failure mode Null exists to prevent."
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
