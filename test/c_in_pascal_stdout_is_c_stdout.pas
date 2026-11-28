{ bug-c-stdout-inside-a-pascal-program-binds-to-pascals-stdout-text }
program c_in_pascal_stdout_is_c_stdout;
uses './c_in_pascal_stdout_is_c_stdout.c';
var r: Integer;
begin
  r := cso_run();
  WriteLn('same pointers: ', r);
end.
