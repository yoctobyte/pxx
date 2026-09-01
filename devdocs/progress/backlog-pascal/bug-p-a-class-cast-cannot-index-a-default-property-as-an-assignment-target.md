---
slug: bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target
title: "`TDerived(b)[3] := v` is refused — `cannot assign to the result of a function call`"
track: P
prio: 45
type: bug
status: backlog
found: 2026-09-02
found-by: frankH
owner: ""
blocked-by: []
summary: "A class cast followed by a DEFAULT-PROPERTY index in assignment-target position is refused: `TDerived(b)[3] := 206` gives `cannot assign to the result of a function call`, where fpc 3.2.2 compiles it and stores 206. The read spelling `x := TDerived(b)[3]` works, so this is the statement-path lvalue walk missing what the expression path has -- the sixth measured instance of [[refactor-p-one-lvalue-path-for-statements-and-expressions]]. Found by the target-shape differential that refactor ticket asks for; 23 of 25 shapes match FPC, and the other two are this and the already-filed string-alias index."
---

# A class cast cannot index a default property as an assignment target

## Repro, with the oracle

```pascal
{$mode objfpc}{$H+}
program t;
type
  TBase = class end;
  TDerived = class(TBase)
    fItems: array[0..3] of Integer;
    function GetItem(i: Integer): Integer;
    procedure SetItem(i, v: Integer);
    property Items[i: Integer]: Integer read GetItem write SetItem; default;
  end;
function TDerived.GetItem(i: Integer): Integer; begin Result := fItems[i]; end;
procedure TDerived.SetItem(i, v: Integer); begin fItems[i] := v; end;
var d: TDerived; b: TBase;
begin
  d := TDerived.Create; b := d;
  TDerived(b)[3] := 206;               { FPC: stores 206 }
  WriteLn(d.fItems[3]);
end.
```

| | |
| --- | --- |
| fpc 3.2.2 | `206` |
| pxx (`42c8796f39ab`) | `pascal26:38: error: cannot assign to the result of a function call` |

**The read spelling compiles.** `x := TDerived(b)[3]` is fine, and so is
`TDerived(b).V := 205` (a named property through the same cast) and
`TDerived(b).fV := 204` (a field). Only the INDEX-as-target arm is missing.

## Why it is filed and not fixed

It is the statement path missing a capability the expression path has — the
shape [[refactor-p-one-lvalue-path-for-statements-and-expressions]] exists for,
and this is its **sixth** measured instance. Patching the class-cast arm to walk
`[` for a default-property write would add yet another hand-rolled walker to the
set that refactor is trying to delete, which is what
`devdocs/dev/normalise-dont-special-case.md` warns against.

**It refuses loudly**, which is why it is 45 and not higher: unlike its two
siblings it produces a diagnostic rather than a wrong value or a corrupted
target, so no program silently does the wrong thing.

## The harness this came from

Built while working the refactor ticket, which asks for exactly this before any
change: *"Sweep with a differential over every target shape (bare, field, index,
deref, cast, property, default property) before and after."*

25 target shapes, each asserting what the target holds after the store, run
against fpc 3.2.2 and pxx. **23 match.** The two that do not:

1. this one;
2. [[bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index]] —
   `TAlias(s)[2] := 'X'` stores nothing, no diagnostic.

A third divergence found by the same sweep — `TAlias(s) := 'zzz'` writing a
managed string through a pointer-shaped target and returning
`len=1073741824` — **was fixed** rather than filed; see
`test/test_alias_cast_assign_target.pas`.

**Take the harness with the refactor.** Its value is that it is now known to be
23/25 green, so a refactor that unifies the two paths has a before-picture
precise enough to be a gate rather than a hope.
