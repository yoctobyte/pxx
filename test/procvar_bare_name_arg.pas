{ REFUSAL FIXTURE -- the same value in ARGUMENT position, which is a different
  code path entirely: TypesCompatible rather than the AN_ASSIGN check, so it
  needs its own rule and its own row. Diagnosed at parse time, hence the
  different message. }
program procvar_bare_name_arg;
type TF = function: Integer;
function G: Integer; begin G := 7; end;
procedure TakesIt(p: TF); begin WriteLn('calling: ', p()); end;
begin
  TakesIt(G);
end.
