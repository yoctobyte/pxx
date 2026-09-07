---
track: P
prio: 75
type: bug
status: open
blocked-by: []
owner: 
summary: "`System.Integer(x)` is handled by STRIPPING the `System.` qualifier, which makes it identical to bare `Integer` -- correct only when nothing shadows `Integer`, and rtl-generics writes the qualifier precisely because something does. Inside `TCompare.UInt8`, `TCompare` declares `class function Integer(constref ALeft, ARight: Integer): Integer`, so after the strip the name binds to that TWO-ARGUMENT METHOD and the parser refuses with `expected ',' before ')'` -- it is parsing an argument list and wants the second argument. The error message IS the diagnosis. 18-line repro, identical on HEAD and pin v407; the same construct with no shadowing member compiles and runs correctly, which is what says the strip is the mechanism. THE STRIP IS THE WRONG OPERATION: the qualifier must SELECT the System scope, not be discarded. This is corpus rung 6a's current wall (generics.defaults:1178) and frankS independently hit the same construct compiling Generics.Collections -- one defect, two files. Wall 1178 was CLEARED on 2026-08-20 by EatSystemQualifier with a different error (`undefined variable (System)`), so the strip itself works and this is the layer behind it."
---

# The `System.` qualifier is stripped rather than resolved, so a shadowing member wins

## Repro — 18 lines

```pascal
program sh;
{$mode delphi}
type
  TCompare = class
    class function Integer(constref ALeft, ARight: Integer): Integer;
    class function UInt8(constref ALeft, ARight: Byte): Integer;
  end;
class function TCompare.Integer(constref ALeft, ARight: Integer): Integer;
begin Result := ALeft - ARight; end;
class function TCompare.UInt8(constref ALeft, ARight: Byte): Integer;
begin
  Result := System.Integer(ALeft) - System.Integer(ARight);
end;
begin
  WriteLn('u8=', TCompare.UInt8(200, 44));
end.
```

| | result |
| --- | --- |
| fpc 3.2.2 | `u8=156` |
| HEAD | `pascal26:15: error: expected ',' before ')'` |
| pin v407 `095ef4811a5b` | identical |

Byte-identical to the corpus failure: `near: := System . Integer ( ALeft >>> ) - System`.

## The error message is the diagnosis

*"expected `,`"* is what a parser says when it is reading an **argument list** and
wants the next argument. `TCompare.Integer` takes two. So after the `System.`
strip the bare name bound to the class's own method and the typecast was parsed
as a call.

## Why the strip is the wrong operation

`EatSystemQualifier` (landed 2026-08-20, and it cleared this very wall with the
*different* error `undefined variable (System)`) removes `System.` and lets the
bare name resolve normally. That is correct exactly when nothing shadows the
name — and **a program only writes `System.Integer` when something does.** The
qualifier is discarded at the moment its only job begins.

The fix is to make the qualifier SELECT a scope rather than vanish: resolve the
tail in the System/builtin scope and never consult the enclosing class. Same
shape as any other qualified lookup.

## The control that says it is the strip

The identical construct with **no shadowing member** compiles and runs on both
HEAD and the pin:

```pascal
var a, b: Byte; r: Integer;
r := System.Integer(a) - System.Integer(b);   { r=156, matches fpc }
```

So `System.`-qualified typecasts are not broken in general. Only the case the
qualifier exists to serve is.

## Do NOT "fix" this by mapping `System.Integer` to the mode's Integer

Recorded on `feature-pascal-corpus-generics.md` and worth repeating because it
inverts the obvious fix: **FPC's `System.Integer` is `SmallInt`.** The 4-byte
`Integer` comes from the MODE, which shadows the system unit's. `SizeOf(System.Integer)`
is `2` under FPC and `4` under pxx — see `compat-p-system-integer-is-smallint-in-fpc`
(prio 15). A fix that resolves the qualified name to the mode's `Integer` would
be right about this program and wrong about the width, so assert identities that
agree under both (`System.LongWord`) rather than the `Integer` spelling.

## Where it bites

- `generics.defaults.pas:1178`, `TCompare.UInt8` — corpus rung 6a's current wall.
- `Generics.Collections`, same construct, found independently by frankS.

One defect, two files, and it is the wall for both.
