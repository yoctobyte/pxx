{ %FAIL-style negative: a REFERENCE-COUNTED element type must be refused.
  What would go on disk is the pointer, so the file is meaningless the moment
  the program exits — FPC refuses the same shape ("Type 'ansistring' is not
  allowed as a file element"). This replaces test_file_type_fail.pas, which
  asserted that `file` itself was refused; that refusal is gone with
  feature-pascal-typed-and-untyped-files and the surviving one is this. }
program test_file_element_type_fail;
var f: file of AnsiString;
begin
end.
