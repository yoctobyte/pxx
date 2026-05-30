program test_procaddr;

{ Verifies @proc: pass the address of a Pascal routine as a C callback.
  libc qsort calls our comparator (cdecl: rdi/rsi = element pointers, rax =
  result), so a correct @CompareInts both yields a real code address and is
  callable. Expected output: 1 2 3 4 5 }

type
  PInteger = ^Integer;

function qsort(base: Pointer; n: LongWord; sz: LongWord; cmp: Pointer): Integer; cdecl; external 'libc.so.6';

var
  arr: array[0..4] of Integer;
  i: Integer;

function CompareInts(pa: PInteger; pb: PInteger): Integer; cdecl;
begin
  CompareInts := pa^ - pb^;
end;

begin
  arr[0] := 5; arr[1] := 3; arr[2] := 1; arr[3] := 4; arr[4] := 2;
  qsort(@arr[0], 5, 4, @CompareInts);
  for i := 0 to 4 do write(arr[i], ' ');
  writeln;
end.
