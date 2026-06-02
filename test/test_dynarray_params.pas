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

{ Writes through the parameter are visible to the caller. }
procedure ScaleArr(arr: array of Integer; by: Integer);
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

  ScaleArr(a, 10);
  Check(a[0] = 10);
  Check(a[1] = 20);
  Check(a[2] = 30);
  Check(a[3] = 40);
  Check(SumArr(a) = 100);

  Check(IsEmpty(empty));
  Check(Count(empty) = 0);
end.
