{ Regression: SetLength on a dynamic-array function Result (incl. a named
  dyn-array type alias as the return type). bug-setlength-dynarray-function-result. }
program test_setlength_dynarray_result;
type TByteArray = array of Byte;

function MakeBytes(n: Integer): TByteArray;
begin
  SetLength(Result, n);
  if n > 0 then Result[0] := 42;
  if n > 1 then Result[1] := 99;
end;

{ literal `array of T` result still works too }
function MakeInts(n: Integer): array of Integer;
begin
  SetLength(Result, n);
  if n > 0 then Result[n - 1] := 7;
end;

var b: TByteArray; ii: array of Integer;
begin
  b := MakeBytes(2);
  writeln(b[0]);
  writeln(b[1]);
  writeln(Length(b));
  ii := MakeInts(3);
  writeln(ii[2]);
  writeln(Length(ii));
end.
