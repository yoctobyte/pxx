---
track: P
prio: 60
type: bug
status: open
blocked-by: []
owner: 
summary: "Two spellings of a BASE class's nested type resolve the TYPE and then fail later, both on real code fpc compiles: a FIELD declared with it (`FSel: TSel` in the derived body) is refused at the ASSIGNMENT with `wrong number of parameters in call to TDer.Twice` -- the method reference is parsed as a CALL because the field's procedural signature was not carried -- and the QUALIFIED spelling `q: TDer.TSel` assigns fine but is refused at the CALL with `expected ')' before '('`. The same two spellings against the class that OWNS the type (`TC.TSel`, field or qualified) work, so it is the INHERITED path specifically, and the type name itself resolves in both -- only the ProcSig does not travel. Split out of the arm-3 UClsParent fix, which repaired the METHOD-IMPLEMENTATION scope and deliberately did not widen these. Not a regression: both fail identically on pin v407."
---

# A base class's nested type resolves but cannot be assigned or called

## Repro

```pascal
program r;
{$mode delphi}
type
  TBase = class
  public type
    TSel = function(a: Integer): Integer of object;
  end;
  TDer = class(TBase)
    FSel: TSel;                     { resolves -- the type name is found }
    function Twice(a: Integer): Integer;
  end;
function TDer.Twice(a: Integer): Integer;
begin Twice := a * 2; end;
var d: TDer; q: TDer.TSel;
begin
  d := TDer.Create;
  d.FSel := d.Twice;                { A: refused, "wrong number of parameters" }
  q := d.Twice;                     { assigns fine }
  WriteLn(q(21));                   { B: refused, "expected ')' before '('" }
end.
```

fpc 3.2.2 compiles and runs both. pxx refuses A, and with A removed refuses B.

## What the pair tells you

| spelling | type resolves | assign | call |
| --- | --- | --- | --- |
| local in a derived METHOD BODY (`var s: TSel`) | yes | yes | yes |
| field of the derived class (`FSel: TSel`) | yes | **no** | — |
| qualified `TDer.TSel` | yes | yes | **no** |
| the same two against the OWNING class (`TC.TSel`) | yes | yes | yes |

**The type name is never the problem** — every row resolves it. What does not
travel along the inheritance path is the alias's **procedural signature**
(`AliasProcSig`), which is what tells the parser that `d.Twice` in that position
is a method REFERENCE rather than a call, and that `q(21)` is a call rather than
a parenthesised expression. Row 1 works because the method-implementation scope
now walks `UClsParent`; rows 2 and 3 reach the alias by other paths that do not.

## Do not reuse the method-pointer framing

The sibling fix's test carries a plain `TAmt = Integer` row precisely because a
procedural-only test reads as a method-pointer bug. Here the procedural-ness IS
the subject — but check an ordinal row before assuming any fix generalises, and
check the owning-class spellings as the control that must stay green.

## Not a regression

Both rows fail identically on pin v407 (`095ef4811a5b`). Long-standing.
