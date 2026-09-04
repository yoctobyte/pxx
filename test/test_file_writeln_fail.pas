{ %FAIL-style negative: a line terminator is a TEXT concept and a record file
  has no lines, so `writeln(f, ...)` over a `file of T` must be refused rather
  than silently writing one record and no newline. FPC refuses it too.
  feature-pascal-typed-and-untyped-files }
program test_file_writeln_fail;
var f: file of Integer; i: Integer;
begin
  Assign(f, 'x'); Rewrite(f); i := 1;
  writeln(f, i);
end.
