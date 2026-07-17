program test_parallel_policy;
{ Policy-aware parallel-for runtime (feature-parallel-for-scheduling-policy):
  drive PXXParallelForP directly (no language surface yet) across every
  distribution and assert each covers [0..N-1] EXACTLY once — miss=0 dup=0. The
  body writes disjoint indices of a global array, so no --threadsafe heap is
  needed, but thread spawn (__pxxclone) still requires --threadsafe. Gate the
  work-stealing paths (pdOnDemand/pdGuided) which partition via an atomic
  counter: a broken fetch-add would drop or double indices. }
uses palparallel;

const N = 10000;
type TA = array[0..N-1] of Integer;
var runc: TA;

procedure Body(ctx: Pointer; lo, hi: NativeInt);
var i: NativeInt;
begin
  for i := lo to hi do runc[i] := runc[i] + 1;
end;

function Ok(const pol: TParPolicy): Boolean;
var i, miss, dup: Integer;
begin
  for i := 0 to N-1 do runc[i] := 0;
  PXXParallelForP(0, N-1, @Body, nil, pol);
  miss := 0; dup := 0;
  for i := 0 to N-1 do
  begin
    if runc[i] = 0 then Inc(miss);
    if runc[i] > 1 then Inc(dup);
  end;
  Ok := (miss = 0) and (dup = 0);
end;

var p: TParPolicy; good: Boolean;
begin
  good := True;
  if not Ok(ParDefault)  then good := False;   { pdChunked }
  if not Ok(ParBalanced) then good := False;   { pdOnDemand, auto chunk }
  if not Ok(ParPolite)   then good := False;   { pdOnDemand + load-aware }
  p := ParBalanced; p.dist := pdGuided;
  if not Ok(p) then good := False;             { pdGuided }
  p := ParBalanced; p.dist := pdOnDemand; p.minChunk := 1;
  if not Ok(p) then good := False;             { finest chunk = worst-case contention }
  p := ParDefault; p.workers := pwFixed; p.fixedN := 3;
  if not Ok(p) then good := False;             { fixed worker count }
  p := ParBalanced; p.workers := pwLoadOnce; p.capPct := 90;
  if not Ok(p) then good := False;             { load-aware, region-entry }
  p := ParBalanced; p.workers := pwLoadCont; p.capPct := 80;
  if not Ok(p) then good := False;             { load-aware, mid-region monitor + parking }
  if good then writeln('PARPOL OK') else writeln('PARPOL FAIL');
end.
