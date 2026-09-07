{ THE POSITIVE HALF, and the one that carries the risk.

  Generalising the argument gate from one candidate to all of them makes it
  reachable by every overloaded method call in the tree. The single-candidate
  gate had to be walked back four times because a KIND PAIR is not a sound
  predicate -- an open array of const, a generic parameter typed tyUnknown at
  its declaration, `nil` into a reference-shaped parameter, and a bare routine
  name used as a procedural value are all LEGAL and all look impossible from
  kinds alone.

  So every one of those classes is here AGAIN, in the shape that only the
  multi-candidate path can reach: a second same-arity overload beside it, so
  the ranker rejects both and the new gate is the thing that decides. Without
  the second overload each of these rows would take the old single-candidate
  path and prove nothing about the change.

  A refusal here is a REGRESSION, not a stricter compiler: fpc 3.2.2 compiles
  and runs this file and prints exactly the rows below. }
{$mode objfpc}{$H+}
program movlok;
type
  TCmp = function(a, b: Pointer): Integer;

  TC = class
    { open array of const beside a same-arity scalar overload }
    procedure Fmt(const args: array of const); overload;
    procedure Fmt(n: LongInt); overload;

    { a procedural parameter beside a same-arity scalar overload: `nil` and a
      bare routine name both reach this }
    procedure SetCmp(c: TCmp); overload;
    procedure SetCmp(n: LongInt); overload;

    { an UNTYPED var parameter, which accepts anything and must keep doing so
      with a sibling overload present }
    procedure Raw(var x); overload;
    procedure Raw(s: string); overload;

    procedure Go;
  end;

function MyCmp(a, b: Pointer): Integer; begin Result := 0; end;

procedure TC.Fmt(const args: array of const); begin WriteLn('fmt ', Length(args)); end;
procedure TC.Fmt(n: LongInt); begin WriteLn('fmt n ', n); end;

procedure TC.SetCmp(c: TCmp); begin if c = nil then WriteLn('cmp nil') else WriteLn('cmp set'); end;
procedure TC.SetCmp(n: LongInt); begin WriteLn('cmp n ', n); end;

procedure TC.Raw(var x); begin WriteLn('raw'); end;
procedure TC.Raw(s: string); begin WriteLn('raw str ', s); end;

procedure TC.Go;
var d: Double; r: LongInt;
begin
  d := 2.5; r := 3;
  { the four abstain classes, each with a same-arity sibling in scope }
  Fmt(['a', 1]);        { array of const: element kind, not the argument's }
  Fmt(7);               { and the scalar sibling still resolves }
  SetCmp(nil);          { nil into a procedural parameter }
  SetCmp(@MyCmp);       { a routine as a value }
  SetCmp(4);            { ...and an INTEGER now reaches the LongInt overload }
  { That row was deliberately ABSENT until 2026-09-07, because pxx bound the
    integer to the PROCEDURAL overload -- on the pinned compiler too, so it
    predated this gate and was not what this file is about. Recording the wrong
    answer in a .expected would have made this fixture go RED the day someone
    fixed it. It is fixed: OverloadArgRank's widening arm asked TypeIsOrdinal,
    which admits tyPointer, so an integer scored a "preferred conversion"
    against a procedural parameter and TIED with the real widening onto LongInt;
    declaration order then decided. It asks TypeIsMachineInt now.
    bug-p-an-integer-argument-binds-a-procedural-overload-over-an-exact-integer-one }
  Raw(d);               { untyped var takes a Double }
  Raw(r);               { ...and a LongInt }
  Raw('lit');           { while the string sibling still wins for a literal }
end;

var c: TC;
begin
  c := TC.Create;
  c.Go;
end.
