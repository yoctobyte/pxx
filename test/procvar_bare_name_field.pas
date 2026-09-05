{ REFUSAL FIXTURE -- the same store through a record FIELD. Separate file
  because the argument arm's diagnostic fires at PARSE time and aborts before
  the assignment arms are lowered, so one file cannot show all four. }
program procvar_bare_name_field;
type TF = function: Integer;
     TR = record f: TF; end;
function G: Integer; begin G := 7; end;
var r: TR;
begin
  r.f := G;
  WriteLn(r.f());
end.
