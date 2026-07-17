program test_parallel_policy_named;
{ `parallel(named args) for` clause (feature-parallel-for-scheduling-policy): the
  named args (bare pd*/pw* enum values, `dist`/`workers` keys, `cap`/`chunk`/`n`
  ints) are constant-folded to five integers and lowered to PXXParallelForN. Each
  form must still cover [0..N-1] exactly once; also check it composes with a
  reduction clause. }
uses palparallel;

const N = 8000;
type TA = array[0..N-1] of Integer;
var runc: TA; good: Boolean;

function CoverOk: Boolean;
var i, miss, dup: Integer;
begin
  miss := 0; dup := 0;
  for i := 0 to N-1 do
  begin
    if runc[i] = 0 then Inc(miss);
    if runc[i] > 1 then Inc(dup);
  end;
  CoverOk := (miss = 0) and (dup = 0);
end;

procedure Run;
var i: Integer; sum: Int64;
begin
  for i := 0 to N-1 do runc[i] := 0;
  parallel(pdOnDemand) for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;

  for i := 0 to N-1 do runc[i] := 0;
  parallel(pdOnDemand, cap 90, chunk 32) for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;

  for i := 0 to N-1 do runc[i] := 0;
  parallel(dist pdGuided, workers pwLoadOnce, cap 80) for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;

  for i := 0 to N-1 do runc[i] := 0;
  parallel(n 3) for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;

  { composes with reduction }
  sum := 0;
  parallel(pdOnDemand, cap 90) for i := 0 to N-1 reduction(+: sum) do sum := sum + i;
  if sum <> Int64(N) * (N - 1) div 2 then good := False;
end;

begin
  good := True;
  Run;
  if good then writeln('PARNAMED OK') else writeln('PARNAMED FAIL');
end.
