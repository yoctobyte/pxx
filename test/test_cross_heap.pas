program test_cross_heap;
{ Heap allocator on cross targets: New/Dispose/GetMem lower to the Pascal
  PXXAlloc/PXXFree in the builtinheap unit, which compiles natively per target.
  Scalar pointers only (record-field access on 32-bit targets is a separate
  backend slice). Output is identical on every target (oracle pattern). }
type
  PRec = ^TRec;
  TRec = record a, b: Integer; end;
var
  p: ^Int64;
  q: ^Integer;
  r: PRec;
  arr: array[0..4] of Integer;
  i: Integer;
  sum: Int64;
begin
  New(p);
  p^ := 123456789;
  writeln(p^);
  Dispose(p);

  New(p);              { reuses the freed block }
  p^ := 42;
  writeln(p^);
  Dispose(p);

  sum := 0;
  for i := 1 to 10 do
  begin
    New(q);
    q^ := i * i;
    sum := sum + q^;
    Dispose(q);
  end;
  writeln(sum);        { 1+4+9+...+100 = 385 }

  { heap-allocated record with field access }
  New(r);
  r^.a := 11; r^.b := 31;
  writeln(r^.a + r^.b);  { 42 }
  Dispose(r);

  { static array indexing }
  for i := 0 to 4 do arr[i] := i * 10;
  writeln(arr[0] + arr[4]);  { 40 }
end.
