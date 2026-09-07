---
track: P
prio: 75
type: bug
status: done
blocked-by: []
owner: frankS
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

## Fixed 2026-09-07 (frankS) — and the diagnosis above is right about the symptom and wrong about the layer

**It is not the strip.** `EatSystemQualifier` already does the right thing:
`ConsumeUnitQualifier` returns **−2** for `System.`, deliberately, and its own
comment says why — *"the builtin soft-aliases must WIN over a same-named method
of the enclosing class"*. The marker was there and it was correct. **One reader
of it was not.**

pasparser_expr.inc, the bare-call-to-a-sibling-static-method arm:

```pascal
if (procIdx < 0) and (idx < 0) and (qUnit < 0) and        { <- admits -2 }
   (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) then
```

`qUnit < 0` **reads** as "not unit-qualified" and **means** "unqualified OR
System-qualified" — and System-qualified is the one case that must not reach a
member of the enclosing class. Its two sibling guards, ~60 lines below and in the
statement-side twin, both spell it `= -1` and both carry the reason. The fix is
`qUnit = -1`.

*The name is not the thing*: a guard whose condition is 80% right about what it
is named after.

## Two things measured that the ticket predicted differently

**The wall is the STATIC-method arm, not the instance one.** The same shadow
declared as an INSTANCE method (`function TBox.Integer`) resolves correctly on
this tree **and on pin v407**. A guard was drafted for the instance dispatch on
the symmetry argument, measured, found to fix nothing, and **reverted** — the
site now carries a comment saying so, because the next reader will have the same
symmetry intuition. `TCompare` is a class of `class function`s, which is what put
the corpus program in the static arm.

**The refusal is the mild face.** With MATCHING arity there is nothing to refuse:

| shadow arity | pin v407 | HEAD |
| --- | --- | --- |
| 2 args, cast passes 1 | `expected ',' before ')'` | `156` |
| 1 arg, cast passes 1 | **`0`** — silently the method's value | `156` |

A silent wrong answer is what let this reach a released compiler, and the
`expected ','` message the ticket read as its own diagnosis is only produced when
the shadow happens not to fit.

## Fixture

`test/test_a_system_qualified_name_beats_a_shadowing_class_member.pas`
(`test_sysqualshadow26`), five rows against fpc 3.2.2. Both faces above, the two
controls that were measured on the pin before being written down (instance
shadow; the construct outside any method), and a width row.

**The width row is `SizeOf(System.LongWord)` and the obvious assertion was
rejected rather than overlooked.** FPC's `System.Integer` is SmallInt — the
4-byte `Integer` comes from the MODE — so a row asserting `SizeOf(System.Integer)
= 4` would pass, would agree with the corpus program that motivated the ticket,
and would encode a rule FPC does not have. `System.LongWord` is 4 under both, so
its answer cannot be reached by accident. The fixture header says this, so nobody
"simplifies" it back.

## What is NOT claimed

**The corpus wall at `generics.defaults:1178` was not re-driven.** The stage
directory this rung uses (`/tmp/generics-stage`) is gone and /tmp is reaped at
6h; rebuilding it is rung 6a's own work. What is measured is the ticket's 18-line
repro, which the ticket states is byte-identical to the corpus failure. Someone
holding rung 6a should re-drive it and move the wall number.

A direct `uses Generics.Defaults` walls EARLIER than 1178 on both HEAD and the
pin, at `FPC_FULLVERSION has no integer value here` — a different gap, not
touched by this.

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
