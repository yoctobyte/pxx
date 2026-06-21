program test_local_typed_const;

{ Routine-local typed constants: array (ordinal + Char) and scalar, read by
  index inside the routine. Output-equal across targets. }

function SumTable: Integer;
const
  T: array[0..3] of Integer = (10, 20, 30, 40);
var
  i, s: Integer;
begin
  s := 0;
  for i := 0 to 3 do
    s := s + T[i];
  SumTable := s;
end;

function Glyph(idx: Integer): Char;
const
  W: array[1..3] of Char = ('a', 'b', 'c');
begin
  Glyph := W[idx];
end;

function Scaled(n: Integer): Integer;
const
  Factor: Integer = 7;
begin
  Scaled := n * Factor;
end;

var
  i: Integer;
begin
  WriteLn(SumTable);          { 100 }
  for i := 1 to 3 do
    WriteLn(Glyph(i));        { a b c }
  WriteLn(Scaled(6));         { 42 }
  { call twice to confirm per-call re-init works }
  WriteLn(SumTable);          { 100 }
end.
