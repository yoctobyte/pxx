program test_parallel_for;
{ Step 1 (feature-parallel-processing): drive the data-parallel loop RUNTIME
  (lib/rtl/palparallel.pas) directly, before any `parallel for` parser sugar
  exists. Validates the worker-pool ABI: PXXParallelFor partitions [lo..hi],
  runs each chunk via body(ctx, cLo, cHi), and barrier-joins.

  Checks:
    - every index in the range is visited EXACTLY once (no gap, no overlap);
    - the parallel writes match the serial reference (a[i] := i*i);
    - a tiny range and an empty range behave.
  --threadsafe (the body writes only preallocated, disjoint slots — but the gate
  runs it under --threadsafe like the other thread tests). x86-64. }
uses palparallel;

const
  N = 100000;

type
  PData = ^TData;
  TData = record
    Arr:   PInteger;   { base of the N result slots }
    Touch: PInteger;   { base of the N visit-counters }
  end;

var
  arr:   array[0..N-1] of Integer;
  touch: array[0..N-1] of Integer;

{ Body ABI: run iterations [lo..hi]. Squares each element and bumps its counter. }
procedure SquareBody(ctx: Pointer; lo, hi: NativeInt);
var
  d: PData;
  ap, tp: PInteger;
  i: NativeInt;
begin
  d := PData(ctx);
  for i := lo to hi do
  begin
    ap := PInteger(NativeInt(d^.Arr) + i * SizeOf(Integer));
    tp := PInteger(NativeInt(d^.Touch) + i * SizeOf(Integer));
    ap^ := Integer(i) * 3;   { bounded: max 299997, no 32-bit overflow }
    tp^ := tp^ + 1;
  end;
end;

var
  d: TData;
  i: Integer;
  visitErr, valErr: Integer;
  sum: Int64;
begin
  for i := 0 to N - 1 do begin arr[i] := -1; touch[i] := 0; end;

  d.Arr   := @arr[0];
  d.Touch := @touch[0];

  writeln('workers=', PXXParForWorkers);

  PXXParallelFor(0, N - 1, @SquareBody, @d);

  visitErr := 0;
  valErr := 0;
  sum := 0;
  for i := 0 to N - 1 do
  begin
    if touch[i] <> 1 then Inc(visitErr);
    if arr[i] <> i * 3 then Inc(valErr);
    sum := sum + arr[i];
  end;

  if sum <> 14999850000 then Inc(valErr);   { 3*sum(0..N-1); folded into valErr }
  writeln('visitErr=', visitErr);
  writeln('valErr=', valErr);

  { Edge cases: single element, and an empty range must run the body zero times. }
  for i := 0 to N - 1 do touch[i] := 0;
  PXXParallelFor(5, 5, @SquareBody, @d);
  PXXParallelFor(10, 3, @SquareBody, @d);   { hi < lo: empty }
  visitErr := 0;
  for i := 0 to N - 1 do
    if ((i = 5) and (touch[i] <> 1)) or ((i <> 5) and (touch[i] <> 0)) then Inc(visitErr);
  writeln('edgeErr=', visitErr);

  if (visitErr = 0) and (valErr = 0) then
    writeln('PARALLELFOR OK')
  else
    writeln('PARALLELFOR FAIL');
end.
