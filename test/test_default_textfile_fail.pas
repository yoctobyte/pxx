{ %FAIL-style negative: Default(TextFile) must be rejected. }
program test_default_textfile_fail;
var t: TextFile;
begin
  t := Default(TextFile);
end.
