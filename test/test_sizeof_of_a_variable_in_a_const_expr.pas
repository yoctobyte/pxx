program test_sizeof_of_a_variable_in_a_const_expr;
{ `sizeof(<a variable or parameter>)` inside a CONSTANT expression -- an array
  bound, a subrange bound, a local const. The bug was that ConstEvalFactor's
  sizeof arm resolved a TYPE NAME through ParseTypeKind only, so a bare symbol
  name reached it and came back `unknown type: d`. FPC's own compiler/entfile.pas
  line 371 writes this shape, which is what settled the "rare in a const
  context" question in the arm's own comment.

  EVERY SIZE HERE IS ONE NO DEFAULT CAN PRODUCE. A `double` parameter answering
  8 is indistinguishable from a slot nobody wrote, because 8 is also the
  pointer-width fallback -- so the record is THREE bytes and the ordinal is a
  Word. And no row asserts a pointer width, so the file is target-independent
  and says the same true thing on i386 as on x86-64. }
type
  entryreal = double;
  TThree = record A, B, C: Byte; end;

{ The ticket's own repro: the bound comes from the enclosing routine's parameter,
  once as an array's upper bound and once as a subrange's. }
function swp(d: entryreal): Integer;
type eb = array[0..sizeof(d)-1] of Byte;
var i: 0..sizeof(d)-1; b: eb;
begin
  for i := Low(eb) to High(eb) do b[i] := i;
  swp := Length(b) + b[3];
end;

{ A size that is neither 8 nor a pointer width. }
function three(r: TThree): Integer;
type rb = array[0..sizeof(r)-1] of Byte;
var b: rb;
begin
  r.A := 0;
  three := Length(b);
end;

{ The DECLARED type, not the passing mode -- `var r` sets IsRef and sizeof(r) is
  still the record's three bytes, not a pointer's eight. }
function threeByRef(var r: TThree): Integer;
type rb = array[0..sizeof(r)-1] of Byte;
var b: rb;
begin
  r.A := 0;
  threeByRef := Length(b);
end;

{ An ordinal narrower than the default, through a local const rather than a bound. }
function wide(w: Word): Integer;
const n = sizeof(w);
begin
  w := 0;
  wide := n;
end;

var t: TThree;
begin
  t.A := 1; t.B := 2; t.C := 3;
  WriteLn(swp(1.0));
  WriteLn(three(t));
  WriteLn(threeByRef(t));
  WriteLn(wide(7));
end.
