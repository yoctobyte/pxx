program test_parallel_for_capture;
{ `parallel for` scalar capture (Phase A): enclosing scalars captured by-ref via
  the frame pointer. Read-capture (base offset) across many workers; write-back
  (single worker, deterministic). --threadsafe, x86-64. }
uses palparallel;

const N = 50000;
var a: array[0..N-1] of Integer;

procedure ReadCap(base: Integer);
var i, k: Integer;
begin
  k := base * 7;                 { captured scalar, read in every iteration }
  parallel for i := 0 to N-1 do
    a[i] := i + k;
end;

procedure WriteCap;
var i, total: Integer;
begin
  total := 0;
  PXXSetParForWorkers(1);        { deterministic: one worker, no reduction race }
  parallel for i := 0 to 99 do
    total := total + i;          { captured scalar write-back through the frame }
  writeln('total=', total);
end;

var i, err: Integer;
begin
  ReadCap(9); err := 0;
  for i := 0 to N-1 do if a[i] <> i + 63 then Inc(err);
  writeln('readErr=', err);
  WriteCap;
  if err = 0 then writeln('PARFORCAP OK') else writeln('PARFORCAP FAIL');
end.
