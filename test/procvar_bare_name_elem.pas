{ REFUSAL FIXTURE -- the same store through an ARRAY ELEMENT. }
program procvar_bare_name_elem;
type TF = function: Integer;
function G: Integer; begin G := 7; end;
var a: array[0..1] of TF;
begin
  a[0] := G;
  WriteLn(a[0]());
end.
