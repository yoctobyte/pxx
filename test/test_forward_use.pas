program test_forward_use;

{ Declaration pre-scan: whole-section forward visibility. None of the references
  below are declared before use, and there is NO `forward` directive anywhere.
  This compiled under the FPC seed (whole-unit resolution) but used to fail the
  self-hosted compiler with "undefined variable". }

{ A routine that calls routines / a const / a type all defined AFTER it. }
procedure SayResult;
var p: TPoint;                          { TPoint declared below }
begin
  WriteLn('square(7) = ', Square(7));   { Square defined below }
  WriteLn('Greeting  = ', Greeting);    { const defined below  }
  WriteLn('sum 1..4  = ', AddUp(4));    { mutual recursion below }
  p := MakePoint(3, 4);
  WriteLn('point     = ', p.x, ',', p.y);
end;

function Square(x: Integer): Integer;
begin
  Square := x * x;
end;

{ A const used before its declaration (above, in SayResult). }
const
  Greeting = 'hello';

{ Mutual recursion with no forward declarations: AddUp <-> AddDown. }
function AddUp(n: Integer): Integer;
begin
  if n <= 0 then
    AddUp := 0
  else
    AddUp := n + AddDown(n - 1);   { AddDown defined after AddUp }
end;

function AddDown(n: Integer): Integer;
begin
  if n <= 0 then
    AddDown := 0
  else
    AddDown := n + AddUp(n - 1);
end;

{ A type used before its declaration (above, in SayResult / MakePoint). }
type
  TPoint = record
    x, y: Integer;
  end;

function MakePoint(a, b: Integer): TPoint;
var r: TPoint;
begin
  r.x := a;
  r.y := b;
  MakePoint := r;
end;

begin
  SayResult;
end.
