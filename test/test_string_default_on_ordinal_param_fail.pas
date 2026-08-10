{ %FAIL-style negative: the mirror image — a string literal defaulting an
  ORDINAL parameter. Same one check, other arm.
  bug-p-integer-default-on-a-string-parameter-is-accepted-and-segfaults }
program test_string_default_on_ordinal_param_fail;
procedure R(k: Integer = 'a');
begin
  writeln(k);
end;
begin
  R();
end.
