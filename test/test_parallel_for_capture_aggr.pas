program test_parallel_for_capture_aggr;
{ `parallel for` NAMED-type aggregate capture (2b B-1): local fixed array, dynamic
  array, and record captured by-ref via the frame pointer. Fixed/record = inline at
  the frame; dyn array = a handle (extra deref). --threadsafe, x86-64. }
uses palparallel;

type
  TGrid = array[0..999] of Integer;
  TDyn  = array of Integer;
  TCfg  = record base, mul: Integer; end;

var okFixed, okDyn, okRec: Integer;

procedure Run;
var g: TGrid; d: TDyn; cfg: TCfg; i: Integer;
begin
  SetLength(d, 1000);
  cfg.base := 7; cfg.mul := 5;
  for i := 0 to 999 do g[i] := -1;

  parallel for i := 0 to 999 do
  begin
    g[i] := cfg.base + i * cfg.mul;   { fixed array + record capture }
    d[i] := g[i] + 1;                  { dyn array (handle) capture }
  end;

  okFixed := 0; okDyn := 0; okRec := 0;
  for i := 0 to 999 do
  begin
    if g[i] = 7 + i*5 then Inc(okFixed);
    if d[i] = g[i] + 1 then Inc(okDyn);
  end;
  if okFixed = 1000 then okRec := 1;
end;

begin
  Run;
  writeln('fixedOK=', okFixed);
  writeln('dynOK=', okDyn);
  if (okFixed = 1000) and (okDyn = 1000) then writeln('PARFORAGGR OK')
  else writeln('PARFORAGGR FAIL');
end.
