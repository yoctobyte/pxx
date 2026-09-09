---
slug: bug-a-a-dynamic-array-value-can-be-assigned-to-a-record-variable
title: "`r := p + q` stores a concatenated ARRAY into a record variable, silently"
track: A
prio: 30
type: bug
blocked-by: []
status: open
created: 2026-09-09
found-by: frankH
summary: "`var p, q: array of TRec; r: TRec;` then `r := p + q` COMPILES and stores the concatenation's array handle into r. Pre-existing and DELIBERATE at the point it is decided: AssignSideKind bails on any node with NodeDynDepth > 0, because it cannot type an array side and its own header ranks a false reject as the worse defect. So the abstention is principled and the accept is the cost of it. fpc 3.2.2 refuses (`Operator is not overloaded: TRecArr + TRecArr`) but for a different reason -- fpc has no dyn-array `+` without {$modeswitch arrayoperators}, while pxx's concatenation is a deliberate feature, so this is NOT a parity row and must not be fixed by removing concatenation. Verified pre-existing against pin `stable_linux_amd64/default/pinned`. The fix is for the assignment check to be able to TYPE an array side, which is the same missing concept as bug-p-an-enum-or-array-type-cannot-be-named-as-an-operator-operand: an array's TypeKind IS its element's, so nothing downstream can tell `array of TRec` from `TRec`."
---

# A dynamic-array value assigned to a record variable is accepted

```pascal
{$mode objfpc}{$H+}
type
  TRec = record v: LongInt; end;
  TRecArr = array of TRec;
var p, q: TRecArr; r: TRec;
begin
  SetLength(p, 1); SetLength(q, 1);
  r := p + q;          { pxx: compiles. r now holds an array HANDLE. }
  WriteLn(r.v);        { reads through it }
end.
```

`p + q` is pxx's dynamic-array concatenation
([[feature-p-dynamic-array-concatenation]]), which is correct and deliberate.
The defect is the STORE: a record variable accepts an array-valued expression.

## Why it is accepted, and why that is not an oversight

`AssignSideKind` (`compiler/ir.inc`) returns False — "this side cannot be
typed" — for any node with `NodeDynDepth > 0`, so the kind check stands down
and the store goes through unchallenged. Its own header ranks the directions:

> a false REJECT of working code is a worse defect than the false accept being
> fixed here

An array's TypeKind IS its element's, so an `array of TRec` node reports
`tyRecord` and a check that trusted the kind would have to be wrong in one
direction or the other. Abstaining was the right call with the tools available.

## What it will take

The assignment check needs to be able to say "this side is an ARRAY of X"
rather than abstaining — the same missing concept as
[[bug-p-an-enum-or-array-type-cannot-be-named-as-an-operator-operand]], where
the operator table could not tell `array of Char` from `Char` and needed a
`REC_ARRAY_OPERAND` key to separate them. `NodeDynDepth` already answers for
every node shape that reaches here, so the information exists; what is missing
is a place to put it in the (kind) pair the check compares.

## Verified pre-existing

`stable_linux_amd64/default/pinned` accepts the program above. It is NOT a
regression of `bug-p-an-enum-or-array-type-cannot-be-named-as-an-operator-operand`
— but that fix did remove an ACCIDENTAL COVER for one narrow shape of it, and
the removal is why it was noticed:

With `operator + (a, b: TRec)` also declared, the pin REFUSED the program with
`arithmetic operator not supported for dynamic arrays`. That refusal was
reached by the operator lookup MATCHING the record operator for an
array-of-record operand — `ResolveNodeRec` answers with the ELEMENT's record —
so the node was retyped, `CheckArithOperandsHaveAMeaning` ran, and the
dyn-array arm fired. A right answer from a wrong match, on a program whose
declaration has nothing to do with it. Keying array operands separately removes
the wrong match, and with it the accidental error, leaving the shape consistent
with the one that never had a record operator in scope.
