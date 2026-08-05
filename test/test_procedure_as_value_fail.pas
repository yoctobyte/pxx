{ %FAIL-style negative: a METHOD declared `procedure` has no result, so it
  cannot be read as a value. This used to COMPILE and yield whatever was in the
  return register — `n := f.DoIt` assigned stack junk and `f.DoArg(3) + 1`
  evaluated to 4, the argument read back out
  (bug-p-procedure-method-in-an-expression-yields-garbage). FPC rejects it as
  "Can't read or write variables of this type". }
program test_procedure_as_value_fail;
type
  TFoo = class
    procedure DoIt;
  end;
procedure TFoo.DoIt; begin end;
var f: TFoo; n: Integer;
begin
  f := TFoo.Create;
  n := f.DoIt;
  writeln(n);
end.
