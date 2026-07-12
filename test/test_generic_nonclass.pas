program test_generic_nonclass;
{$mode objfpc}
type
  generic TPair<T> = record
    a, b: T;
  end;
  TIntPair = specialize TPair<Integer>;
  generic TArr<T> = array of T;
  TIntArr = specialize TArr<Integer>;
  generic TFn<T> = function(x: T): T;
  TIntFn = specialize TFn<Integer>;
function Dbl(x: Integer): Integer;
begin
  Result := x * 2;
end;
var p: TIntPair; xs: TIntArr; f: TIntFn; i: Integer;
begin
  p.a := 3; p.b := 4;
  writeln(p.a + p.b);
  SetLength(xs, 3);
  for i := 0 to 2 do xs[i] := i * 10;
  writeln(xs[2]);
  f := @Dbl;
  writeln(f(21));
end.
