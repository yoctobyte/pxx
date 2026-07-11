{ %FAIL-style negative: class var inside a record type (terecs12c/13c). }
program test_record_class_var_fail;
type
  TRec = record
  class var
    X: Integer;
  end;
begin
end.
