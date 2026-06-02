program test_dynarray_result;

{ Dynamic arrays as function results. The result is a pointer-sized heap
  handle built via SetLength(Result, ...); returning it transfers the handle
  to the caller, who can index it and query its Length. }

var
  a: array of Integer;
  i, sum: Integer;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

function MakeSquares(n: Integer): array of Integer;
var i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do
    Result[i] := i * i;
end;

{ Zero-length result is a valid empty array. }
function MakeEmpty: array of Integer;
begin
  SetLength(Result, 0);
end;

begin
  a := MakeSquares(5);
  Check(Length(a) = 5);
  Check(a[0] = 0);
  Check(a[1] = 1);
  Check(a[2] = 4);
  Check(a[3] = 9);
  Check(a[4] = 16);

  sum := 0;
  for i := 0 to Length(a) - 1 do
    sum := sum + a[i];
  Check(sum = 30);

  { Reassigning from a fresh result releases the previous allocation. }
  a := MakeSquares(3);
  Check(Length(a) = 3);
  Check(a[2] = 4);

  a := MakeEmpty;
  Check(Length(a) = 0);
end.
