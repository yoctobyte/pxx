program test_parallel_for_lang;
{ Language-level `parallel for` (feature-parallel-processing). Exercises the
  parse-time desugaring: soft keyword, worker synthesis, PXXParallelFor dispatch.
  v1: body references the loop var + globals only (capture support is a follow-up).
  --threadsafe, x86-64. }
uses palparallel;

const N = 100000;
var
  arr:   array[0..N-1] of Integer;
  touch: array[0..N-1] of Integer;

procedure Run;
var i, visitErr, valErr: Integer;
begin
  for i := 0 to N-1 do begin arr[i] := -1; touch[i] := 0; end;

  { data-parallel: each iteration writes its own disjoint slots }
  parallel for i := 0 to N-1 do
  begin
    arr[i] := i * 3;
    touch[i] := touch[i] + 1;
  end;

  visitErr := 0; valErr := 0;
  for i := 0 to N-1 do
  begin
    if touch[i] <> 1 then Inc(visitErr);
    if arr[i] <> i * 3 then Inc(valErr);
  end;
  writeln('visitErr=', visitErr);
  writeln('valErr=', valErr);
  if (visitErr = 0) and (valErr = 0) then writeln('PARFORLANG OK')
  else writeln('PARFORLANG FAIL');
end;

begin
  Run;
end.
