{ REFUSAL FIXTURE for test_procvar_bare_name_binding. `f := G` with no `@`,
  outside {$mode delphi}: G is read as a CALL (which is FPC's reading too --
  its message says got "LongInt"), and the Integer result lands in a slot that
  is called as a code address. Compiled clean and SIGSEGV'd.
  Must be refused with `cannot assign Integer to Pointer`. }
program procvar_bare_name_var;
type TF = function: Integer;
function G: Integer; begin G := 7; end;
var f: TF;
begin
  f := G;
  WriteLn(f());
end.
