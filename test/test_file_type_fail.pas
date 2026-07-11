{ %FAIL-style negative: untyped `file` type must be rejected. }
program test_file_type_fail;
type TUntypedFile = file;
var t: TUntypedFile;
begin
end.
