---
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`TC.K` for a class const compiles and `c.K` on an instance of the same class answers `\"K\": no such member on this record/class`. fpc accepts both. The class VAR sibling was fixed -- pasparser_lval.inc:5436 reaches FindClassVar through a non-bare receiver, with a comment naming it as the sibling arm of a double case -- and the class CONST beside it was never added, so FindClassConst has no receiver-path caller at all. Blocks the fifth member kind in bug-p-a-nested-routine-sees-only-two-of-its-classs-five-member-kinds: that fix desugars an implicit member reference to `__nestself.<name>`, which for a class const lands on exactly this refusal."
---

# A class const is unreachable through an instance receiver

- **Type:** bug (compat) — **Track P** (`compiler/pasparser_lval.inc`, and
  however many of the member-dispatch copies turn out to need it).
- Found backing a class const out of
  [[bug-p-a-nested-routine-sees-only-two-of-its-classs-five-member-kinds]]
  after it made that fix produce a different wrong answer.

## Repro

```pascal
{$mode objfpc}
type TC = class public const K = 5; class var CV: Integer; end;
var c: TC;
begin
  c := TC.Create; TC.CV := 9;
  WriteLn(TC.K, ' ', TC.CV);   { pxx: 5 9        fpc: 5 9 }
  WriteLn(c.K,  ' ', c.CV);    { pxx: REFUSED    fpc: 5 9 }
end.
```

`pascal26: error: "K": no such member on this record/class`. **`c.CV` on the
line's other half is fine**, which is the shape of the thing: the class VAR
reaches the receiver path and the class CONST does not.

## Where

`pasparser_lval.inc:5436` calls `FindClassVar(recId - REC_UCLASS_BASE,
fieldName)` under a comment that already names this as a double case:

> *Class variable / class ATTRIBUTE reached through a NON-BARE receiver — the
> same fall-through the bare-identifier path already does in ParseFactor. A
> class-written class attribute has no instance field BY CONSTRUCTION, so
> without this arm `Base(1).made` reaches RequireRecMember and dies as "no such
> member" while `b.made` on the very same object works — the sibling arm of a
> double case (normalise-dont-special-case.md).*

Every word of that applies to a class const, and the const was not added.
`FindClassConst` (`pasparser_class.inc:351`) has **no receiver-path caller**:
its consumers all reach it from a bare name inside the declaring class.

## Scope, which is the part to establish before starting

`FindClassVar` has **sixteen** call sites across `pasparser_lval.inc`,
`pasparser_expr.inc`, `pasparser_class.inc` and `pasparser_decl.inc`, of which
several are receiver-path member dispatch and several are bare-name lookup.
`pasparser_expr.inc:1541` calls itself *"this FOURTH copy of member dispatch"*.
**Do not add one call beside one `FindClassVar` and close this** — that is how
the class-var arm came to exist without its const twin. Find which of the
sixteen are the receiver path, and pair them.

## Why it is prio 40 rather than lower

It is the ordinary way a class const is spelled from outside the class when you
have an instance to hand, and the diagnostic actively misdirects: `"K": no such
member` reads as a typo in the const's NAME, so the natural response is to go
and check the declaration, which is correct.

## Gate

Both rows of the repro matching fpc; the class-VAR rows in the same file
unchanged (they are the control that the receiver path was not disturbed); and,
once this lands, `FindClassConst` added back to the nested-routine
free-variable scan in `pasparser_decl.inc` with a class-const row in
`test/test_a_nested_routine_reaches_all_its_classs_member_kinds.pas` — the
comment there says exactly what to re-enable.
