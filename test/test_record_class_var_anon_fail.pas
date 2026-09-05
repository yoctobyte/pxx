{ %FAIL-style negative: `class var` in an ANONYMOUS record. The other half of
  the narrowing in test_record_class_var_fail.pas -- there is no type name to
  qualify the access with, so there is nothing to write `T.X` as. }
program test_record_class_var_anon_fail;
var
  r: record
  class var
    X: Integer;
  end;
begin
end.
