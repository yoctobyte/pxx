{ %FAIL-style negative: Default() on a record containing a file field. }
program test_default_filefield_fail;
type TRec = record f: TextFile; end;
var r: TRec;
begin
  r := Default(TRec);
end.
