program test_a_distinct_type_is_a_different_type_for_overloads;
{ `T = type Base` is FPC's strong typedef: layout-identical to Base and a
  DIFFERENT type for overload resolution. pxx parsed the keyword and then
  produced an ordinary alias, so the two overloads collapsed into one row with
  `duplicate definition of 'P' with the same parameter types` and both calls ran
  the last body.

  ROWS C..H ARE THE CONTROLS AND EVERY ONE OF THEM WAS GREEN BEFORE THE FIX.
  They are the whole risk of this change: distinctness is decided at the
  COMPARISON and never at registration, so an ORDINARY alias (`type TInt =
  Integer`, no keyword) must go on binding an Integer parameter, and a distinct
  type must go on being assignment-compatible with its base in both directions,
  which is what FPC does. A file with only rows A and B in it passes just as
  well when every alias in the tree has been made to stop matching.

  A LITERAL IS NOT IN THIS FILE AND THE REASON IS A MEASUREMENT: fpc 3.2.2
  answers `Can't determine which overloaded function to call` for `P(5)` once
  the two overloads are genuinely distinct, because 5 fits both. pxx binds the
  base overload. Accepting what FPC rejects is not a defect (the parity ceiling
  in CLAUDE.md), so the row would be ours by construction and could not carry an
  oracle -- and asserting our own answer for an input FPC calls ambiguous is
  asserting a coin flip.
  bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct }
type
  TMyB = type byte;      { DISTINCT }
  TInt = Integer;        { an ordinary alias, no keyword }
  TAlsoB = byte;         { ...and one over the same base as TMyB }

procedure P(b: byte);   begin WriteLn('A: base'); end;
procedure P(m: TMyB);   begin WriteLn('B: distinct'); end;

procedure Q(i: Integer); begin WriteLn('C: ', i); end;
procedure R(b: byte);    begin WriteLn('D: ', b); end;

{ SINGLE-CANDIDATE routines: there is nothing to prefer, so distinctness must
  not refuse. These three are the rows that caught the first version of the fix,
  which made distinctness a COMPATIBILITY rule and refused all three -- fpc 3.2.2
  compiles and runs every one. }
procedure VB(var v: byte);  begin v := v + 1; end;
procedure VM(var v: TMyB);  begin v := 100; end;
procedure BV(v: TMyB);      begin WriteLn('J: ', Ord(v)); end;

var
  x: TMyB;
  b: byte;
  n: TInt;
  a: TAlsoB;
begin
  x := 5; b := 1; n := 7; a := 9;

  P(b);                  { the base overload }
  P(x);                  { the distinct one }

  Q(n);                  { C: an ORDINARY alias still binds its base parameter }
  R(a);                  { D: ...and so does a second alias over the same base }

  b := x;                { E/F: assignment-compatible in BOTH directions, as in FPC }
  WriteLn('E: ', b);
  x := b + 1;
  WriteLn('F: ', Ord(x));

  P(byte(x));            { G: an explicit cast to the base -> the base overload }

  { H/I/J: one candidate, so nothing to prefer and nothing may be refused --
    a distinct type stays assignment-compatible with its base in BOTH
    directions, and by REFERENCE as well as by value. }
  VB(x);   WriteLn('H: ', Ord(x));
  VM(b);   WriteLn('I: ', b);
  BV(b);
end.
