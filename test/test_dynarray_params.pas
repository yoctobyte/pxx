program test_dynarray_params;

{ Dynamic arrays as procedure/function parameters (open-array convention:
  the parameter slot borrows the caller's heap data pointer, so Length reads
  the heap header and element writes are visible to the caller). }

var
  a: array of Integer;
  i: Integer;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

{ Length over a parameter reads the heap header, not a static sentinel. }
function Count(arr: array of Integer): Integer;
begin
  Result := Length(arr);
end;

{ Read elements through the parameter. }
function SumArr(arr: array of Integer): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Length(arr) - 1 do
    Result := Result + arr[i];
end;

{ A VALUE open array is COPIED, as FPC does, so writes through it are NOT
  visible to the caller (fix(A) 635b231b9; verified against FPC directly —
  `caller sees: 1 2 3 4`). This test asserted the opposite until 2026-08-07,
  which is why it went red: the FIX landed without updating the test, and the
  watcher auto-filed the resulting failure as a regression. It was a stale
  expectation, not a code regression. }
procedure ScaleArr(arr: array of Integer; by: Integer);
var i: Integer;
begin
  for i := 0 to Length(arr) - 1 do
    arr[i] := arr[i] * by;
end;

{ ...and the VAR form still aliases, which is the other half of the same
  distinction and the reason the copy has to be conditional rather than
  unconditional. Pinned here so a future change cannot "fix" one by breaking
  the other. }
procedure ScaleArrVar(var arr: array of Integer; by: Integer);
var i: Integer;
begin
  for i := 0 to Length(arr) - 1 do
    arr[i] := arr[i] * by;
end;

{ An unallocated array passed in has Length 0. }
function IsEmpty(arr: array of Integer): Boolean;
begin
  Result := Length(arr) = 0;
end;

var
  empty: array of Integer;

begin
  SetLength(a, 4);
  for i := 0 to 3 do
    a[i] := i + 1;

  Check(Count(a) = 4);
  Check(SumArr(a) = 10);

  { VALUE parameter: the callee scales its own copy, the caller is untouched }
  ScaleArr(a, 10);
  Check(a[0] = 1);
  Check(a[1] = 2);
  Check(a[2] = 3);
  Check(a[3] = 4);
  Check(SumArr(a) = 10);

  { VAR parameter: the callee scales the caller's array in place }
  ScaleArrVar(a, 10);
  Check(a[0] = 10);
  Check(a[3] = 40);
  Check(SumArr(a) = 100);

  Check(IsEmpty(empty));
  Check(Count(empty) = 0);
end.
