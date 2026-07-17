program test_parallel_policy_lang;
{ `parallel(P) for` language surface (feature-parallel-for-scheduling-policy):
  the policy clause lowers to PXXParallelForPP(@P). Assert bare + every preset +
  a mutated var policy all cover [0..N-1] exactly once, and that `parallel` is
  still a normal identifier when NOT a parallel-for (the soft-keyword rule). }
uses palparallel;

const N = 5000;
type TA = array[0..N-1] of Integer;
var runc: TA;

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

{ `parallel` used as an ordinary function name — must NOT be parsed as a loop. }
function parallel(x: Integer): Integer;
begin parallel := x + 1; end;

var good: Boolean;

procedure Run;
var i: Integer; myPol: TParPolicy;
begin
  for i := 0 to N-1 do runc[i] := 0;
  parallel for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;

  for i := 0 to N-1 do runc[i] := 0;
  parallel(ParBalanced) for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;

  for i := 0 to N-1 do runc[i] := 0;
  parallel(ParPolite) for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;

  myPol := ParBalanced; myPol.dist := pdGuided;
  for i := 0 to N-1 do runc[i] := 0;
  parallel(myPol) for i := 0 to N-1 do runc[i] := runc[i] + 1;
  if not CoverOk then good := False;
end;

begin
  good := True;
  Run;
  { soft-keyword: normal call, not a loop }
  if parallel(41) <> 42 then good := False;
  if good then writeln('PARPOLLANG OK') else writeln('PARPOLLANG FAIL');
end.
