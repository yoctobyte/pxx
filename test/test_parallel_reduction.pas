program test_parallel_reduction;
{ `reduction(op: v)` clause (feature-parallel-for-scheduling-policy): each worker
  accumulates a PRIVATE partial and folds it into the shared reduction variable
  under PXXReduceLock, so shared accumulation is race-free (the by-ref capture
  hazard). Assert exact deterministic results for + (Int64 and Double) and xor,
  with and without a policy clause. }
uses palparallel;

const N = 200000;
type TA = array[0..N-1] of Integer;
var good: Boolean; a: TA;

procedure Run;
var i, isum, mx, mn: Integer; sum, xr: Int64; fsum: Double;
begin
  { + Int64: 0+1+...+N-1 = N*(N-1)/2 }
  sum := 0;
  parallel for i := 0 to N-1 reduction(+: sum) do sum := sum + i;
  if sum <> Int64(N) * (N - 1) div 2 then good := False;

  { + Integer (keyword type — exercises the __pfred0 keyword-token path) }
  isum := 0;
  parallel for i := 0 to 1000 reduction(+: isum) do isum := isum + 1;
  if isum <> 1001 then good := False;

  { + Double: 0.25 * N }
  fsum := 0;
  parallel(ParBalanced) for i := 0 to N-1 reduction(+: fsum) do fsum := fsum + 0.25;
  if (fsum < N * 0.25 - 0.5) or (fsum > N * 0.25 + 0.5) then good := False;

  { xor: 0 xor 1 xor ... xor N-1; for N mod 4 = 0 the result is 0 }
  xr := 0;
  parallel(ParBalanced) for i := 0 to N-1 reduction(xor: xr) do xr := xr xor i;
  if xr <> 0 then good := False;

  { min / max over a pseudo-random spread; index 0 forced to the extremes }
  for i := 0 to N-1 do a[i] := (i * 1103515245 + 12345) mod 1000000;
  a[0] := 999999; a[1] := 0;
  mx := a[0];
  parallel(ParBalanced) for i := 0 to N-1 reduction(max: mx) do if a[i] > mx then mx := a[i];
  if mx <> 999999 then good := False;
  mn := a[0];
  parallel for i := 0 to N-1 reduction(min: mn) do if a[i] < mn then mn := a[i];
  if mn <> 0 then good := False;
end;

var r: Integer;
begin
  good := True;
  for r := 1 to 4 do Run;   { repeat: a reduction race would show as a flaky sum }
  if good then writeln('PARRED OK') else writeln('PARRED FAIL');
end.
